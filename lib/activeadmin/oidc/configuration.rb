# frozen_string_literal: true

module ActiveAdmin
  module Oidc
    class Configuration
      DEFAULT_SCOPE               = 'openid email profile'
      DEFAULT_TIMEOUT             = 5
      DEFAULT_IDENTITY_ATTRIBUTE  = :email
      DEFAULT_IDENTITY_CLAIM      = :email
      DEFAULT_LOGIN_BUTTON_LABEL  = 'Sign in with SSO'
      DEFAULT_ADMIN_USER_CLASS    = 'AdminUser'
      DEFAULT_ACCESS_DENIED_MESSAGE =
        'Your account has no permission to access this admin panel.'
      DEFAULT_LOGIN_PATH  = '/admin/login'
      DEFAULT_LOGOUT_PATH = '/admin/logout'
      DEFAULT_STUB_DEV_ENV_LOGIN_CLAIMS = {
        'sub'   => 'stub-uid',
        'email' => 'stub-dev@example.com'
      }.freeze

      attr_accessor :issuer, :client_id, :client_secret, :scope,
                    :redirect_uri,
                    :login_button_label, :timeout,
                    :identity_attribute, :identity_claim,
                    :access_denied_message, :on_login, :admin_user_class,
                    :login_path, :logout_path

      # Readers, not writers: stub login is turned on through
      # `stub_dev_env_login!` so the environment check cannot be skipped.
      # Specs (this gem's own included) stub these two instead of
      # pretending to run in the development environment.
      attr_reader :stub_dev_env_login_claims_block

      def initialize
        reset!
      end

      def reset!
        @issuer                = nil
        @client_id             = nil
        @client_secret         = nil
        @scope                 = DEFAULT_SCOPE
        @redirect_uri          = nil
        @login_button_label    = DEFAULT_LOGIN_BUTTON_LABEL
        @timeout               = DEFAULT_TIMEOUT
        @identity_attribute    = DEFAULT_IDENTITY_ATTRIBUTE
        @identity_claim        = DEFAULT_IDENTITY_CLAIM
        @access_denied_message = DEFAULT_ACCESS_DENIED_MESSAGE
        @admin_user_class      = DEFAULT_ADMIN_USER_CLASS
        @login_path            = DEFAULT_LOGIN_PATH
        @logout_path           = DEFAULT_LOGOUT_PATH
        @on_login              = nil
        @pkce_override         = nil
        @stub_dev_env_login = false
        @stub_dev_env_login_claims_block = nil
        self
      end

      def pkce
        return @pkce_override unless @pkce_override.nil?

        client_secret.nil? || client_secret.to_s.empty?
      end

      def pkce=(value)
        @pkce_override = value
      end

      # Turns on the development stub login: the login page's button
      # signs in with locally fabricated claims instead of redirecting to
      # the IdP. For machines whose redirect URI the IdP does not know --
      # a non-default port, or two apps sharing one OIDC client.
      #
      # A no-op outside the development environment, so there is nothing
      # to guard at boot and nothing to flip off before a deploy.
      #
      # The optional block receives the default claims and returns the
      # claims to sign in with, so a host whose `on_login` reads roles or
      # groups can satisfy it:
      #
      #   c.stub_dev_env_login! { |claims| claims.merge('groups' => ADMIN_GROUP) }
      #
      # The claims go through the same UserProvisioner as a real
      # callback, so a block that does not satisfy `on_login` is denied
      # exactly as the real IdP would deny it.
      def stub_dev_env_login!(&block)
        return false unless ::Rails.env.development?

        @stub_dev_env_login = true
        @stub_dev_env_login_claims_block = block
        true
      end

      def stub_dev_env_login_enabled?
        @stub_dev_env_login
      end

      # Evaluated once per stub sign-in, in the controller. String keys
      # all the way down, the same shape `on_login` receives from a real
      # callback.
      #
      # The block may either return a Hash or mutate the one it is given
      # -- `claims["groups"] = [...]` as a last line returns the assigned
      # value, not the Hash, and that should not 500 the dev's login.
      def stub_dev_env_login_claims
        claims = DEFAULT_STUB_DEV_ENV_LOGIN_CLAIMS.dup
        block  = stub_dev_env_login_claims_block
        if block
          returned = block.call(claims)
          claims = returned if returned.is_a?(Hash)
        end
        claims.deep_transform_keys(&:to_s)
      end

      # Where the login page's single button POSTs to: the stub route
      # while stub login is on, the real OmniAuth entry point otherwise.
      def login_submit_path
        return "#{login_path}/stub" if stub_dev_env_login_enabled?

        "#{::OmniAuth.config.path_prefix}/#{Engine::PROVIDER_NAME}"
      end

      def validate!
        raise ConfigurationError, 'issuer is required'    if issuer.blank?
        raise ConfigurationError, 'client_id is required' if client_id.blank?
        raise ConfigurationError, 'on_login is required'  if on_login.nil?
        raise ConfigurationError, 'on_login must be callable (respond to #call)' unless on_login.respond_to?(:call)

        true
      end
    end
  end
end
