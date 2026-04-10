# frozen_string_literal: true

require "rails/engine"

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
        klass&.respond_to?(:devise_modules) && klass.devise_modules.include?(:omniauthable)
      end

      ControllersPatch = Module.new do
        def controllers
          result = super
          if Engine.oidc_enabled?
            result = result.merge(
              omniauth_callbacks: "active_admin/oidc/devise/omniauth_callbacks"
            )
          end
          result
        end
      end

      initializer "activeadmin_oidc.register_controllers" do |app|
        app.config.to_prepare do
          require "active_admin/devise"
          unless ::ActiveAdmin::Devise.singleton_class < ControllersPatch
            ::ActiveAdmin::Devise.singleton_class.prepend(ControllersPatch)
          end
        end
      end

      initializer "activeadmin_oidc.prepend_view_paths" do |app|
        app.config.to_prepare do
          if Engine.oidc_enabled?
            require "active_admin/devise"
            view_path = File.expand_path("../../../app/views", __dir__)
            ::ActiveAdmin::Devise::SessionsController.prepend_view_path(view_path)
          end
        end
      end

      initializer "activeadmin_oidc.filter_parameters" do |app|
        app.config.filter_parameters |= %i[code id_token access_token refresh_token state nonce]
      end
    end
  end
end
