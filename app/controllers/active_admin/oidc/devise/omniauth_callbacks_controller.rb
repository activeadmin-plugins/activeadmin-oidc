# frozen_string_literal: true

require 'devise'

module ActiveAdmin
  module Oidc
    module Devise
      # Handles the OAuth callback from the IdP. Wiring:
      #
      #   # config/routes.rb (or inside ActiveAdmin::Devise.config)
      #   devise_for :admin_users, ActiveAdmin::Devise.config.merge(
      #     controllers: {
      #       omniauth_callbacks: "active_admin/oidc/devise/omniauth_callbacks"
      #     }
      #   )
      #
      # The action name matches the provider name registered with Devise
      # (`:oidc`, from ActiveAdmin::Oidc::Engine::PROVIDER_NAME).
      class OmniauthCallbacksController < ::Devise::OmniauthCallbacksController
        def oidc
          auth  = request.env['omniauth.auth'] || {}
          info  = auth['info'] || {}
          # Defensive: an OIDC strategy is supposed to put a Hash at
          # extra.raw_info, but a misbehaving/custom strategy could
          # set something else (String, nil, Array). We only trust a
          # Hash-shaped value; anything else collapses to {} and we
          # rebuild `sub`/`email` from the top-level auth hash below.
          extra = auth.dig('extra', 'raw_info')
          extra = {} unless extra.is_a?(Hash)

          claims = extra.to_h.transform_keys(&:to_s)
          claims['sub']   = auth['uid'] if claims['sub'].blank? && auth['uid'].present?
          claims['email'] = info['email'] if claims['email'].blank? && info['email'].present?

          admin_user = UserProvisioner.new(
            ActiveAdmin::Oidc.config,
            claims: claims,
            provider: ActiveAdmin::Oidc::Engine::PROVIDER_NAME.to_s
          ).call

          # Devise checks active_for_authentication? on session
          # deserialization but NOT on initial OmniAuth sign-in.
          # Guard here so disabled/locked users are rejected immediately.
          unless admin_user.active_for_authentication?
            message = admin_user.inactive_message
            flash[:alert] = I18n.t("devise.failure.#{message}", default: message.to_s)
            redirect_to after_omniauth_failure_path_for(resource_name)
            return
          end

          sign_in_and_redirect admin_user, event: :authentication
          set_flash_message(:notice, :success, kind: 'OIDC') if is_navigational_format?
        rescue ActiveAdmin::Oidc::ProvisioningError => e
          Rails.logger.warn("[activeadmin-oidc] denial: #{e.message}")
          flash[:alert] = ActiveAdmin::Oidc.config.access_denied_message
          redirect_to after_omniauth_failure_path_for(resource_name)
        end

        def failure
          Rails.logger.warn("[activeadmin-oidc] omniauth failure: #{failure_message}")
          flash[:alert] = ActiveAdmin::Oidc.config.access_denied_message
          redirect_to after_omniauth_failure_path_for(resource_name)
        end

        private

        # Land on the ActiveAdmin namespace root after a successful SSO
        # sign-in instead of Devise's default (host app root). Hosts
        # that don't define a `/` route would otherwise hit a routing
        # error immediately after login, and even when `/` does exist
        # it's rarely what an admin user wants to see. ActiveAdmin
        # always mounts at `/admin`, so we go there directly.
        def after_sign_in_path_for(resource)
          stored_location_for(resource) || '/admin'
        end

        # Devise's `new_session_path(scope)` is only generated when
        # `:database_authenticatable` is in the mapping's `used_helpers`,
        # so an OIDC-only model never gets it. The engine mounts
        # `new_<scope>_session_path` itself, but the helper lives on
        # whichever route set Devise's URL helper dispatcher points at:
        # the per-mapping `router_name` (set by
        # `devise_for :scope, router_name: :engine`) when present,
        # otherwise the global `Devise.available_router_name`
        # (set by `Devise.router_name = :engine`), which defaults to
        # `:main_app`. Replicate that dispatcher here so the helper is
        # resolved on the right context (Rails.application proxy or
        # mounted engine proxy).
        def after_omniauth_failure_path_for(scope)
          router_name = ::Devise.mappings[scope].router_name ||
                        ::Devise.available_router_name
          send(router_name).public_send(:"new_#{scope}_session_path")
        end
      end
    end
  end
end
