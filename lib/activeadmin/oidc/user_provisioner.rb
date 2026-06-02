# frozen_string_literal: true

module ActiveAdmin
  module Oidc
    # Finds-or-creates an AdminUser for an OIDC callback. Runs the host's
    # `on_login` hook (which owns all authorization decisions), then saves.
    #
    #   provisioner = UserProvisioner.new(config, claims: merged_claims, provider: "oidc")
    #   admin_user  = provisioner.call  # raises ProvisioningError on denial
    #
    # Strategy:
    #
    # 1. Look up by (provider, uid). If found → update.
    # 2. Otherwise look up by the configured identity_attribute. If that row
    #    is already locked to a different (provider, uid) → refuse
    #    (account-takeover guard). Otherwise adopt it.
    # 3. Otherwise build a new record.
    # 4. Assign the identity attribute and oidc_raw_info.
    # 5. Call config.on_login(admin_user, claims). Falsy → deny. Truthy →
    #    save and return.
    #
    # The claims hash is passed through untouched except that `access_token`
    # and `refresh_token` (if present) are never persisted.
    class UserProvisioner
      # Claim keys that must never land in oidc_raw_info.
      BLOCKED_RAW_INFO_KEYS = %w[access_token refresh_token id_token].freeze

      def initialize(config, claims:, provider:)
        @config   = config
        @claims   = claims.transform_keys(&:to_s)
        @provider = provider
      end

      def call
        validate_claims!

        admin_user = find_or_adopt_or_build

        # Retry path: a concurrent first sign-in inserted between our
        # initial miss-and-build and our failed save. Return the
        # winner's row verbatim — on_login already ran on our (now
        # discarded) in-memory build, and re-firing it would double
        # any host-side side effects (audit log, webhook, email).
        return admin_user if @retried

        assign_base_attributes(admin_user)

        allowed = invoke_on_login(admin_user)
        raise ProvisioningError, denial_message unless allowed

        # Devise's `active_for_authentication?` guard runs in the
        # controller post-sign-in, but by then we've already saved
        # the record. Hostile attempts where on_login flips an
        # inactivity flag (e.g. enabled=false) would otherwise leave
        # provisional rows in the DB on every try. Refuse before
        # persisting.
        unless admin_user.active_for_authentication?
          raise ProvisioningError, admin_user.inactive_message.to_s
        end

        save!(admin_user)
        admin_user
      rescue RetryProvisioning
        # Concurrent JIT provisioning: another thread inserted first.
        # Re-run once — find_or_adopt_or_build will now find the record.
        retry
      end

      private

      def model
        @model ||= resolve_admin_user_class
      end

      def resolve_admin_user_class
        @config.admin_user_class.is_a?(Class) ? @config.admin_user_class : @config.admin_user_class.constantize
      end

      def validate_claims!
        if @claims["sub"].blank?
          raise ProvisioningError, "OIDC id_token is missing a sub claim"
        end

        claim_key = @config.identity_claim.to_s
        if @claims[claim_key].blank?
          raise ProvisioningError,
                "OIDC id_token is missing identity claim #{claim_key.inspect}"
        end
      end

      def find_or_adopt_or_build
        uid = @claims["sub"].to_s
        existing = model.find_by(provider: @provider, uid: uid)
        return existing if existing

        identity_value = @claims[@config.identity_claim.to_s]
        identity_match = model.find_by(@config.identity_attribute => identity_value)

        if identity_match
          if identity_match.provider.present? || identity_match.uid.present?
            raise ProvisioningError,
                  "Identity #{identity_value.inspect} is already linked to a different account (takeover guard)"
          end

          # Adoption of a pre-existing row (provider/uid still nil) by
          # an IdP-supplied identity value is a privilege-escalation
          # vector when the IdP allows external / unverified emails:
          # an attacker registers `ceo@example.com` at the IdP and
          # adopts the seeded admin row. Refuse when the IdP explicitly
          # marks the claim as unverified. (Absent claim → unchanged
          # behaviour, since many IdPs don't ship `email_verified` at
          # all.)
          if @claims["email_verified"] == false
            raise ProvisioningError,
                  "Identity #{identity_value.inspect} is not verified by the IdP — refusing adoption"
          end

          identity_match.provider = @provider
          identity_match.uid      = uid
          return identity_match
        end

        model.new(provider: @provider, uid: uid)
      end

      def assign_base_attributes(admin_user)
        identity_value = @claims[@config.identity_claim.to_s]
        admin_user.public_send("#{@config.identity_attribute}=", identity_value)
        admin_user.oidc_raw_info = sanitized_raw_info if admin_user.respond_to?(:oidc_raw_info=)
      end

      def sanitized_raw_info
        @claims.reject { |k, _v| BLOCKED_RAW_INFO_KEYS.include?(k) }
      end

      def save!(admin_user)
        admin_user.save!
      rescue ActiveRecord::RecordNotUnique
        raise ProvisioningError, denial_message if @retried

        # Concurrent JIT provisioning race: the other thread won the
        # insert. Re-run call once to find the now-persisted record.
        @retried = true
        raise RetryProvisioning
      rescue ActiveRecord::RecordInvalid => e
        raise ProvisioningError, e.message
      end

      # The on_login hook is host-app code. If it raises a non-gem
      # exception, we do NOT want the callback action to blow up with
      # a 500 — the cleanest UX is the same generic denial flash the
      # "hook returned false" path produces. We still log the original
      # exception class + message at error level so ops can debug.
      # Gem-internal exceptions (ActiveAdmin::Oidc::Error subclasses)
      # are re-raised untouched so nested provisioning errors surface
      # with their original messages.
      def invoke_on_login(admin_user)
        @config.on_login.call(admin_user, @claims)
      rescue ActiveAdmin::Oidc::Error
        raise
      rescue StandardError => e
        ActiveAdmin::Oidc.logger.error(
          "[activeadmin-oidc] on_login hook raised #{e.class}: #{e.message}"
        )
        raise ProvisioningError, denial_message
      end

      def denial_message
        @config.access_denied_message
      end
    end
  end
end
