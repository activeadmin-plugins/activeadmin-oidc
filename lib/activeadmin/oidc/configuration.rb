# frozen_string_literal: true

module ActiveAdmin
  module Oidc
    class Configuration
      DEFAULT_SCOPE               = "openid email profile"
      DEFAULT_TIMEOUT             = 5
      DEFAULT_IDENTITY_ATTRIBUTE  = :email
      DEFAULT_IDENTITY_CLAIM      = :email
      DEFAULT_LOGIN_BUTTON_LABEL  = "Sign in with SSO"
      DEFAULT_ACCESS_DENIED_MESSAGE =
        "Your account has no permission to access this admin panel."

      attr_accessor :issuer, :client_id, :client_secret, :scope,
                    :login_button_label, :timeout,
                    :identity_attribute, :identity_claim,
                    :access_denied_message, :on_login

      def initialize
        reset!
      end

      def reset!
        @issuer                = nil
        @client_id             = nil
        @client_secret         = nil
        @scope                 = DEFAULT_SCOPE
        @login_button_label    = DEFAULT_LOGIN_BUTTON_LABEL
        @timeout               = DEFAULT_TIMEOUT
        @identity_attribute    = DEFAULT_IDENTITY_ATTRIBUTE
        @identity_claim        = DEFAULT_IDENTITY_CLAIM
        @access_denied_message = DEFAULT_ACCESS_DENIED_MESSAGE
        @on_login              = nil
        @pkce_override         = nil
        self
      end

      def pkce
        return @pkce_override unless @pkce_override.nil?

        client_secret.nil? || client_secret.to_s.empty?
      end

      def pkce=(value)
        @pkce_override = value
      end

      def preset(name)
        case name
        when :zitadel
          require "activeadmin/oidc/presets/zitadel"
          Presets::Zitadel.apply(self)
        else
          raise ConfigurationError, "Unknown preset: #{name.inspect}"
        end
      end

      def validate!
        raise ConfigurationError, "issuer is required"    if issuer.blank?
        raise ConfigurationError, "client_id is required" if client_id.blank?
        raise ConfigurationError, "on_login is required"  if on_login.nil?
        unless on_login.respond_to?(:call)
          raise ConfigurationError, "on_login must be callable (respond to #call)"
        end

        true
      end
    end
  end
end
