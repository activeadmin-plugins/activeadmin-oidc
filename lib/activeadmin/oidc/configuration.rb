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
      # Stands in for ActiveAdmin's namespace when ActiveAdmin is not
      # loaded (plain unit specs, scripts) and it therefore cannot be
      # read. Everything else derives from
      # `ActiveAdmin.application.default_namespace`.
      FALLBACK_NAMESPACE = :admin

      attr_accessor :issuer, :client_id, :client_secret, :scope,
                    :redirect_uri,
                    :login_button_label, :timeout,
                    :identity_attribute, :identity_claim,
                    :access_denied_message, :on_login, :admin_user_class
      attr_writer :login_path, :logout_path,
                  :omniauth_path_prefix, :omniauth_route_prefix

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
        @login_path            = nil
        @logout_path           = nil
        @omniauth_path_prefix  = nil
        @omniauth_route_prefix = nil
        @on_login              = nil
        @pkce_override         = nil
        self
      end

      # The paths below all hang off ActiveAdmin's namespace, which the
      # host can rename (`config.default_namespace = :backoffice`) -- in
      # which case there is no /admin anywhere in the app and every
      # hardcoded one would 404. They are computed on read rather than in
      # `reset!` because the gem's own initializer may run before the
      # host's `ActiveAdmin.setup` block.
      #
      # `login_path` and `logout_path` are declared inside whichever route
      # set holds the host's Devise mapping, so an engine-mounted host has
      # to override them engine-relative -- the mount prefix is prepended
      # on top of whatever is written here.
      def login_path
        @login_path || "#{active_admin_namespace_prefix}/login"
      end

      def logout_path
        @logout_path || "#{active_admin_namespace_prefix}/logout"
      end

      # Where the OmniAuth middleware listens. This one is a real,
      # browser-visible path: the middleware sits in the application's
      # Rack stack and sees the URL before any engine mount prefix has
      # been stripped.
      def omniauth_path_prefix
        @omniauth_path_prefix || "#{active_admin_namespace_prefix}/auth"
      end

      # What Devise declares its OmniAuth request/callback routes with.
      # Devise reuses a single setting for both jobs, and the two differ
      # by exactly the mount prefix when `devise_for` lives inside a
      # mounted engine -- so an engine-mounted host sets this
      # engine-relative ('/auth'), the same way it does `login_path`.
      def omniauth_route_prefix
        @omniauth_route_prefix || omniauth_path_prefix
      end

      # ActiveAdmin's namespace as a Symbol, or nil for the root
      # namespace (`default_namespace = false`), which mounts everything
      # at the top level.
      def active_admin_namespace
        namespace = active_admin_default_namespace
        return nil if namespace.blank? || namespace.to_sym == :root

        namespace.to_sym
      end

      # Narrow on purpose: `NoMethodError` is what "ActiveAdmin is not
      # loaded, or not set up yet" surfaces as. Anything else -- a host
      # initializer blowing up inside its own `default_namespace`
      # override, say -- is a real misconfiguration and must not be
      # quietly turned into a wrong path.
      def active_admin_default_namespace
        return FALLBACK_NAMESPACE unless defined?(::ActiveAdmin) && ::ActiveAdmin.respond_to?(:application)

        ::ActiveAdmin.application.default_namespace
      rescue NoMethodError
        FALLBACK_NAMESPACE
      end

      def active_admin_namespace_prefix
        namespace = active_admin_namespace
        namespace ? "/#{namespace}" : ''
      end

      def pkce
        return @pkce_override unless @pkce_override.nil?

        client_secret.nil? || client_secret.to_s.empty?
      end

      def pkce=(value)
        @pkce_override = value
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
