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
      DEFAULT_STUB_LOGIN_BUTTON_LABEL = 'Sign in with stub login (no IdP)'
      DEFAULT_STUB_LOGIN_CLAIMS = {
        'sub'   => 'stub-uid',
        'email' => 'stub@example.com'
      }.freeze

      attr_accessor :issuer, :client_id, :client_secret, :scope,
                    :redirect_uri,
                    :login_button_label, :timeout,
                    :identity_attribute, :identity_claim,
                    :access_denied_message, :on_login, :admin_user_class,
                    :login_path, :logout_path,
                    :stub_login_enabled, :stub_login_claims,
                    :stub_login_button_label

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
        @stub_login_enabled    = false
        @stub_login_claims     = DEFAULT_STUB_LOGIN_CLAIMS
        @stub_login_button_label = DEFAULT_STUB_LOGIN_BUTTON_LABEL
        self
      end

      def pkce
        return @pkce_override unless @pkce_override.nil?

        client_secret.nil? || client_secret.to_s.empty?
      end

      def pkce=(value)
        @pkce_override = value
      end

      def stub_login_enabled?
        !!@stub_login_enabled
      end

      # True when there is enough configuration to start a real
      # authorization code flow. Stub-login-only setups (a dev machine
      # with no IdP credentials at all) deliberately leave these blank,
      # and the login view hides the SSO button rather than rendering
      # one that 404s.
      def sso_configured?
        issuer.present? && client_id.present?
      end

      # `stub_login_claims` may be a Hash or any callable returning one
      # (so hosts can read ENV per request and switch dev identities
      # without editing the initializer). Always returns String keys,
      # the same shape `on_login` receives.
      def resolved_stub_login_claims
        raw = stub_login_claims
        raw = raw.call if raw.respond_to?(:call)
        (raw || {}).to_h.transform_keys(&:to_s)
      end

      # The stub claims go through the same UserProvisioner as a real
      # callback, which needs `sub` and the configured identity claim.
      # Checking here (at boot for Hash claims, per request for
      # callables) turns a misconfiguration into a readable message
      # instead of the provisioner's generic access-denied flash.
      def validate_stub_login!(claims = resolved_stub_login_claims)
        if claims['sub'].blank?
          raise ConfigurationError, 'stub_login_claims must contain a "sub" value'
        end

        key = identity_claim.to_s
        if claims[key].blank?
          raise ConfigurationError,
                "stub_login_claims must contain #{key.inspect} (the configured identity_claim)"
        end

        true
      end

      def validate!
        unless stub_login_enabled?
          raise ConfigurationError, 'issuer is required'    if issuer.blank?
          raise ConfigurationError, 'client_id is required' if client_id.blank?
        end
        raise ConfigurationError, 'on_login is required'  if on_login.nil?
        raise ConfigurationError, 'on_login must be callable (respond to #call)' unless on_login.respond_to?(:call)

        true
      end
    end
  end
end
