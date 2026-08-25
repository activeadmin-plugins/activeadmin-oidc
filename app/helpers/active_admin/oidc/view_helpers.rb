# frozen_string_literal: true

module ActiveAdmin
  module Oidc
    # View helpers for the login page. Mixed into
    # `ActiveAdmin::Devise::SessionsController` by the engine, so they are
    # available both to the gem's own login view and to a host app that
    # ships its own `app/views/active_admin/devise/sessions/new.html.erb`
    # (in which case the engine backs off and the host must render the
    # buttons itself).
    module ViewHelpers
      def activeadmin_oidc_config
        ActiveAdmin::Oidc.config
      end

      # True when a real authorization code flow can be started. False on
      # a stub-login-only setup with no IdP credentials at all, where a
      # rendered SSO button would just 404 (no OmniAuth strategy, hence
      # no middleware listening on /admin/auth/oidc).
      def activeadmin_oidc_sso_configured?
        activeadmin_oidc_config.sso_configured?
      end

      def activeadmin_oidc_sso_login_path
        "#{OmniAuth.config.path_prefix}/#{ActiveAdmin::Oidc::Engine::PROVIDER_NAME}"
      end

      # True when the stub login button should be rendered. Mirrors the
      # conditions under which the engine draws the route, so the button
      # is never shown without a target.
      def activeadmin_oidc_stub_login_enabled?
        activeadmin_oidc_config.stub_login_enabled? &&
          !::Rails.env.production? &&
          activeadmin_oidc_stub_login_path.present?
      end

      # Resolved through the same router the Devise mapping uses, so it
      # is correct when Devise (and therefore our routes) live inside a
      # mounted engine. Returns nil when the route is not drawn.
      def activeadmin_oidc_stub_login_path
        scope = ActiveAdmin::Oidc::Engine.admin_user_class.model_name.singular
        router = ::Devise.mappings[scope.to_sym]&.router_name ||
                 ::Devise.available_router_name
        send(router).public_send(:"#{scope}_stub_login_path")
      rescue NoMethodError
        nil
      end

      # The identity the stub button will sign in as, for the warning
      # banner. Nil when the claims are unusable, so the banner can say
      # so instead of raising inside a view.
      def activeadmin_oidc_stub_login_identity
        claims = activeadmin_oidc_config.resolved_stub_login_claims
        claims[activeadmin_oidc_config.identity_claim.to_s].presence
      end
    end
  end
end
