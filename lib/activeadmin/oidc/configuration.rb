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
      DEFAULT_STUB_DEV_ENV_LOGIN_CLAIMS = {
        'sub'   => 'stub-uid',
        'email' => 'stub-dev@example.com'
      }.freeze
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
        @login_path            = nil
        @logout_path           = nil
        @omniauth_path_prefix  = nil
        @omniauth_route_prefix = nil
        @on_login              = nil
        @pkce_override         = nil
        @stub_dev_env_login = false
        @stub_dev_env_login_claims_block = nil
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

        # `omniauth_path_prefix`, not `OmniAuth.config.path_prefix`:
        # under an engine mount those two differ by the mount prefix,
        # and this one is the browser-visible path the form posts to.
        "#{omniauth_path_prefix}/#{Engine::PROVIDER_NAME}"
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
