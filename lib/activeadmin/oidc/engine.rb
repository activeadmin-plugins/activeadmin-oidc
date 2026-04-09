# frozen_string_literal: true

require "rails/engine"

module ActiveAdmin
  module Oidc
    # Mountable Rails engine. Ships the OmniauthCallbacksController the host
    # app's Devise setup routes to, and exposes the hardcoded callback path
    # all hosts share.
    class Engine < ::Rails::Engine
      # OmniAuth strategy name. The callback URL in the host app is
      #   <host>/admin/auth/oidc/callback
      # (ActiveAdmin mounts Devise under /admin by default.) Zitadel and
      # other IdPs support multiple redirect URIs per app, so hardcoding
      # this path keeps config surface small with no real downside.
      PROVIDER_NAME = :oidc

      # Prepended into ActiveAdmin::Devise's singleton class so that
      # `ActiveAdmin::Devise.controllers` includes the gem's omniauth
      # callbacks controller without any host-app wiring.
      ControllersPatch = Module.new do
        def controllers
          super.merge(
            omniauth_callbacks: "active_admin/oidc/devise/omniauth_callbacks"
          )
        end
      end

      # Apply the patch once ActiveAdmin::Devise is loadable. We use
      # `to_prepare` rather than a regular initializer because
      # `active_admin/devise` references `::Devise::SessionsController`
      # at file load, and that constant isn't autoloadable until
      # ActionDispatch has set up controller autoload paths — which
      # only happens after the initializer phase.
      initializer "activeadmin_oidc.register_controllers" do |app|
        app.config.to_prepare do
          require "active_admin/devise"
          unless ::ActiveAdmin::Devise.singleton_class < ControllersPatch
            ::ActiveAdmin::Devise.singleton_class.prepend(ControllersPatch)
          end
        end
      end

      # Make sure the gem's login view override wins over ActiveAdmin's
      # default. ActiveAdmin's view path is registered when its engine
      # initializes; we prepend ours in `to_prepare` so it lands in front
      # of ActiveAdmin's Devise::SessionsController view lookup.
      initializer "activeadmin_oidc.prepend_view_paths" do |app|
        app.config.to_prepare do
          require "active_admin/devise"
          view_path = File.expand_path("../../../app/views", __dir__)
          ::ActiveAdmin::Devise::SessionsController.prepend_view_path(view_path)
        end
      end

      # Prevent OAuth codes, tokens and CSRF/replay guards from ever
      # landing in Rails logs. If the host app crashes mid-callback
      # Rails will dump the full params hash into the log; we merge
      # the known-sensitive keys into `filter_parameters` so they
      # come out as [FILTERED]. The host app's own filter_parameters
      # are preserved — we only add.
      #
      # `state` and `nonce` aren't "secret" in the strong sense, but
      # they're single-use session-bound values and treating them as
      # opaque in logs is the industry default.
      initializer "activeadmin_oidc.filter_parameters" do |app|
        app.config.filter_parameters |= %i[code id_token access_token refresh_token state nonce]
      end
    end
  end
end
