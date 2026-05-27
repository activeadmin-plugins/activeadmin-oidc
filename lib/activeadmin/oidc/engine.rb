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
        admin_class = ActiveAdmin::Oidc.config.admin_user_class
        klass = admin_class.is_a?(String) ? admin_class.safe_constantize : admin_class
        klass.respond_to?(:devise_modules) && klass.devise_modules.include?(:omniauthable)
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

      # Rails 8 lazy-loads routes; OmniAuth's failure handler walks
      # `Devise.mappings.find_by_path!` which sees an empty mapping
      # registry and raises "Could not find a valid mapping for path
      # /admin/auth/oidc", masking the real underlying error (CSRF,
      # mis-issued id_token, etc). Forcing route load at after_initialize
      # populates the registry before the first OmniAuth callback hits.
      config.after_initialize do
        Rails.application.routes_reloader.execute_unless_loaded
      end
    end
  end
end
