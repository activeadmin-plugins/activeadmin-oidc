# frozen_string_literal: true

require 'rails/engine'

module ActiveAdmin
  module Oidc
    class Engine < ::Rails::Engine
      PROVIDER_NAME = :oidc

      # True once the host has supplied the minimum OIDC credentials.
      def self.configured?
        cfg = ActiveAdmin::Oidc.config
        cfg.issuer.present? && cfg.client_id.present?
      end

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
      #
      # Ordered after the host's config/initializers (where
      # `ActiveAdmin.setup` and `Devise.setup` live, so the namespace and
      # any explicit host overrides are readable) and before
      # `devise.omniauth`, which both needs the strategy registered and
      # builds the middleware from these args.
      #
      # `path_prefix` is passed per-strategy rather than left to
      # `OmniAuth.config.path_prefix`, because Devise overwrites that
      # global at route-draw time with `Devise.omniauth_path_prefix` --
      # the value it *declares its routes* with, which for a mounted
      # engine is the same path minus the mount prefix. Setting the two
      # independently through the global is impossible: Devise raises
      # "Wrong OmniAuth configuration" whenever they disagree.
      initializer 'activeadmin_oidc.register_omniauth_strategy',
                  after: :load_config_initializers, before: 'devise.omniauth' do
        cfg = ActiveAdmin::Oidc.config
        next unless Engine.configured?

        require 'omniauth_openid_connect'

        # `||=` semantics preserved: a host that set the prefix in its
        # own devise.rb keeps it. Read by Devise when the routes are
        # drawn, which happens later still.
        ::Devise.omniauth_path_prefix ||= cfg.omniauth_route_prefix

        ::Devise.setup do |devise|
          devise.omniauth :openid_connect,
                          name: PROVIDER_NAME,
                          path_prefix: cfg.omniauth_path_prefix,
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

          cfg         = ActiveAdmin::Oidc.config
          login_path  = cfg.login_path
          logout_path = cfg.logout_path
          scope_name  = Engine.admin_user_class.model_name.singular.to_sym

          Engine.session_routes_target(app).append do
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
            end
          end
        end
      end
    end
  end
end
