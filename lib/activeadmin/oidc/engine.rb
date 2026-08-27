# frozen_string_literal: true

require 'rails/engine'

module ActiveAdmin
  module Oidc
    class Engine < ::Rails::Engine
      PROVIDER_NAME = :oidc

      # True when the host's AdminUser model includes :omniauthable.
      # Used to gate controller registration and view overrides so the
      # gem is a no-op when OIDC is not enabled on the model.
      def self.oidc_enabled?
        klass = admin_user_class
        klass.respond_to?(:devise_modules) && klass.devise_modules.include?(:omniauthable)
      end

      def self.admin_user_class
        admin_class = ActiveAdmin::Oidc.config.admin_user_class
        admin_class.is_a?(String) ? admin_class.safe_constantize : admin_class
      end

      # Returns the route set our session routes should be appended to.
      # Follows `Devise.available_router_name` (set by the host via
      # `Devise.router_name = :foo`) so that engine-mounted Devise
      # setups see the helpers on the right engine's url_helpers.
      def self.session_routes_target(app)
        router_name = ::Devise.available_router_name
        return app.routes if router_name.blank? || router_name.to_sym == :main_app

        engine_class = ::Rails::Engine.subclasses.find do |klass|
          klass.engine_name.to_sym == router_name.to_sym
        end

        engine_class ? engine_class.routes : app.routes
      end

      ControllersPatch = Module.new do
        def controllers
          result = super
          if Engine.oidc_enabled?
            result = result.merge(
              omniauth_callbacks: 'active_admin/oidc/devise/omniauth_callbacks'
            )
          end
          result
        end
      end

      initializer 'activeadmin_oidc.register_controllers' do |app|
        app.config.to_prepare do
          require 'active_admin/devise'
          unless ::ActiveAdmin::Devise.singleton_class < ControllersPatch
            ::ActiveAdmin::Devise.singleton_class.prepend(ControllersPatch)
          end
        end
      end

      initializer 'activeadmin_oidc.prepend_view_paths' do |app|
        app.config.to_prepare do
          if Engine.oidc_enabled?
            require 'active_admin/devise'
            # Only prepend the gem's SSO-only login view if the host app
            # doesn't ship its own override. This avoids the need for hosts
            # to re-prepend their views after the gem.
            host_view = ::Rails.root.join(
              'app/views/active_admin/devise/sessions/new.html.erb'
            )
            unless host_view.exist?
              view_path = File.expand_path('../../../app/views', __dir__)
              ::ActiveAdmin::Devise::SessionsController.prepend_view_path(view_path)
            end
          end
        end
      end

      # Automatically register the OmniAuth :openid_connect strategy with
      # Devise when the gem is configured, so host apps don't have to
      # duplicate the config.omniauth boilerplate in devise.rb.
      # Runs before Devise's own initializer so the strategy is available
      # when the model calls `devise :omniauthable`.
      initializer 'activeadmin_oidc.register_omniauth_strategy', before: 'devise.omniauth' do
        cfg = ActiveAdmin::Oidc.config
        next if cfg.issuer.blank? || cfg.client_id.blank?

        require 'omniauth_openid_connect'

        ::Devise.setup do |devise|
          # ActiveAdmin mounts Devise under /admin, so OmniAuth middleware
          # must intercept /admin/auth/:provider.
          devise.omniauth_path_prefix ||= '/admin/auth'

          devise.omniauth :openid_connect,
                          name: PROVIDER_NAME,
                          scope: (cfg.scope || 'openid email profile').split,
                          response_type: :code,
                          issuer: cfg.issuer,
                          discovery: true,
                          pkce: cfg.pkce,
                          client_options: {
                            identifier: cfg.client_id,
                            secret: cfg.client_secret.presence,
                            redirect_uri: cfg.redirect_uri,
                            port: nil,
                            scheme: nil,
                            host: nil
                          }.compact
        end

        # Devise propagates omniauth_path_prefix to
        # OmniAuth.config.path_prefix during route generation
        # (set_omniauth_path_prefix!). On Rails 8 routes load lazily,
        # so the OmniAuth middleware may process requests before routes
        # are drawn and miss the prefix. Set it eagerly here.
        # Must happen AFTER `devise.omniauth` because that call
        # triggers autoload of devise/omniauth which nils the value.
        ::OmniAuth.config.path_prefix = ::Devise.omniauth_path_prefix
      end

      initializer 'activeadmin_oidc.filter_parameters' do |app|
        app.config.filter_parameters |= %i[code id_token access_token refresh_token state nonce]
      end

      # The gem is OIDC-first: mount our SSO landing page at /admin/login
      # and a warden-based /admin/logout under the existing devise scope.
      # Without these, hosts that omit :database_authenticatable have no
      # session routes from Devise at all, so ActiveAdmin's redirect to
      # `new_admin_user_session_path` 404s. Hosts that DO keep
      # :database_authenticatable get our SSO landing on GET; Devise's
      # POST /admin/login (password sign-in) is unaffected because it
      # lives on the same path with a different verb.
      #
      # Mount target follows `Devise.available_router_name`: hosts that
      # mount Devise inside an engine set `Devise.router_name = :admin_panel`,
      # which pins Devise URL helpers to `AdminPanel::Engine.routes`. We
      # mount in the same route set so
      # `<Engine>.routes.url_helpers.new_admin_user_session_path` resolves.
      # Defaults to `Rails.application.routes` when unset.
      initializer 'activeadmin_oidc.mount_oidc_sessions_routes' do |app|
        # after_initialize fires once at boot. `RouteSet#clear!` deliberately
        # preserves the append/prepend queues across reloads, so re-running
        # this hook (as `to_prepare` would in dev) accumulates duplicate
        # append callbacks and crashes the second draw with
        # "Invalid route name, already in use: 'new_admin_user_session'".
        app.config.after_initialize do
          next unless Engine.oidc_enabled?

          Engine.session_routes_target(app).append do
            # Read at draw time (not in the enclosing after_initialize)
            # so `Rails.application.reload_routes!` picks up host changes
            # to any of them.
            cfg         = ActiveAdmin::Oidc.config
            login_path  = cfg.login_path
            logout_path = cfg.logout_path
            scope_name  = Engine.admin_user_class.model_name.singular.to_sym

            devise_scope scope_name do
              # Use the controller class directly via `.action(...)` so
              # isolated engines don't try to resolve the controller as
              # `<Engine>::ActiveAdmin::Devise::SessionsController` from
              # the relative string form.
              get login_path, to: ::ActiveAdmin::Devise::SessionsController.action(:new), as: :"new_#{scope_name}_session"

              # Mirror what AA's own Devise integration does in
              # lib/active_admin/devise.rb: accept whichever HTTP
              # methods Devise.sign_out_via and
              # ActiveAdmin.application.logout_link_method combine to.
              # Read at route-draw time (not in the enclosing
              # after_initialize) so `Rails.application.reload_routes!`
              # picks up host changes to either value — useful for
              # specs that stub the setting and re-evaluate routes.
              # AA 4 dropped `logout_link_method` (its layout uses
              # `button_to` + Turbo), so only consult the setting when
              # the version still exposes it.
              aa_app = ::ActiveAdmin.application
              aa_method = aa_app.logout_link_method if aa_app.respond_to?(:logout_link_method)
              logout_via = [*::Devise.sign_out_via, aa_method].compact.uniq

              match logout_path, to: ::ActiveAdmin::Devise::SessionsController.action(:destroy), as: :"destroy_#{scope_name}_session", via: logout_via

              # Development stub login. `stub_dev_env_login!` only ever
              # sets the flag in the development environment, so the
              # route simply does not exist anywhere else -- and a route
              # that is never drawn cannot be probed.
              if cfg.stub_dev_env_login_enabled?
                # Resolve the controller per request instead of capturing
                # `.action(:stub)` at draw time: the class lives in the
                # engine's app/ and is reloadable, and stub login runs in
                # development where a captured constant goes stale on the
                # first reload. A lambda also sidesteps the module scoping
                # an isolated engine would apply to a string target.
                # `login_submit_path` is what the login button posts to,
                # so drawing the route from it keeps the two in step.
                post cfg.login_submit_path,
                     to: ->(env) { ::ActiveAdmin::Oidc::Devise::OmniauthCallbacksController.action(:stub).call(env) },
                     as: :"#{scope_name}_stub_login"
              end
            end
          end
        end
      end
    end
  end
end
