# frozen_string_literal: true

require "devise"

module ActiveAdmin
  module Oidc
    module Devise
      # Handles the OAuth callback from the IdP. Wiring:
      #
      #   # config/routes.rb (or inside ActiveAdmin::Devise.config)
      #   devise_for :admin_users, ActiveAdmin::Devise.config.merge(
      #     controllers: {
      #       omniauth_callbacks: "active_admin/oidc/devise/omniauth_callbacks"
      #     }
      #   )
      #
      # The action name matches the provider name registered with Devise
      # (`:oidc`, from ActiveAdmin::Oidc::Engine::PROVIDER_NAME).
      class OmniauthCallbacksController < ::Devise::OmniauthCallbacksController
        def oidc
          auth   = request.env["omniauth.auth"] || {}
          info   = auth["info"] || {}
          extra  = auth.dig("extra", "raw_info") || {}

          claims = extra.to_h.transform_keys(&:to_s)
          claims["sub"]   = auth["uid"] if claims["sub"].blank? && auth["uid"].present?
          claims["email"] = info["email"] if claims["email"].blank? && info["email"].present?

          admin_user = UserProvisioner.new(
            ActiveAdmin::Oidc.config,
            claims:   claims,
            provider: ActiveAdmin::Oidc::Engine::PROVIDER_NAME.to_s
          ).call

          sign_in_and_redirect admin_user, event: :authentication
          set_flash_message(:notice, :success, kind: "OIDC") if is_navigational_format?
        rescue ActiveAdmin::Oidc::ProvisioningError => e
          Rails.logger.warn("[activeadmin-oidc] denial: #{e.message}")
          flash[:alert] = ActiveAdmin::Oidc.config.access_denied_message
          redirect_to after_omniauth_failure_path_for(resource_name)
        end

        def failure
          Rails.logger.warn("[activeadmin-oidc] omniauth failure: #{failure_message}")
          flash[:alert] = ActiveAdmin::Oidc.config.access_denied_message
          redirect_to after_omniauth_failure_path_for(resource_name)
        end

        private

        # Land on the ActiveAdmin namespace root after a successful SSO
        # sign-in instead of Devise's default (host app root). Hosts
        # that don't define a `/` route would otherwise hit a routing
        # error immediately after login, and even when `/` does exist
        # it's rarely what an admin user wants to see. ActiveAdmin
        # always mounts at `/admin`, so we go there directly.
        def after_sign_in_path_for(resource)
          stored_location_for(resource) || "/admin"
        end
      end
    end
  end
end
