# frozen_string_literal: true

require "engine_rails_helper"

# Engine-mounted Devise + OIDC scenario:
#
#   - AdminPanel::Engine is a non-isolated Rails engine
#   - `devise_for :admin_users` (NO `router_name:` option) lives inside
#     the engine's routes
#   - `Devise.router_name = :admin_panel` is set globally in the
#     devise initializer — this pins Devise's URL helpers to the
#     engine via `Devise.available_router_name` rather than the
#     per-mapping option
#
# The global-only setup is the more common pattern in real hosts. The
# OmniauthCallbacks failure handler must therefore fall back to
# `Devise.available_router_name` when `Devise.mappings[scope].router_name`
# is nil — calling the helper directly on the controller blows up
# because the helper lives on the engine proxy, not on main_app.
RSpec.feature "Engine-mounted OIDC sessions", type: :feature do
  it "AdminPanel::Engine.routes.url_helpers exposes new_admin_user_session_path" do
    expect {
      AdminPanel::Engine.routes.url_helpers.new_admin_user_session_path
    }.not_to raise_error
  end

  it "AdminPanel::Engine.routes.url_helpers exposes destroy_admin_user_session_path" do
    expect {
      AdminPanel::Engine.routes.url_helpers.destroy_admin_user_session_path
    }.not_to raise_error
  end

  it "the engine's route table contains GET /admin/login" do
    paths = AdminPanel::Engine.routes.routes.map { |r| [r.verb, r.path.spec.to_s] }
    expect(paths).to include(["GET", "/admin/login(.:format)"])
  end

  scenario "Capybara visit to /admin/login renders the SSO landing page" do
    visit "/admin/login"
    expect(page.status_code).to eq(200)
    expect(page.body).to include(ActiveAdmin::Oidc.config.login_button_label)
  end

  scenario "/admin redirect from ActiveAdmin's authenticate_admin_user! lands on /admin/login" do
    visit "/admin"
    expect(page).to have_current_path("/admin/login")
  end

  context "OmniAuth failure path under global Devise.router_name" do
    # Sanity-check the dummy setup so a future refactor that flips it
    # back to per-mapping `router_name:` makes the regression scenario
    # below stop covering the global-only code path explicitly.
    it "dummy_engine has no per-mapping router_name (relies on the global setting)" do
      expect(Devise.mappings[:admin_user].router_name).to be_nil
      expect(Devise.available_router_name.to_sym).to eq(:admin_panel)
    end

    around do |ex|
      saved = OmniAuth.config.mock_auth[:oidc]
      OmniAuth.config.mock_auth[:oidc] = :invalid_credentials
      ex.run
      OmniAuth.config.mock_auth[:oidc] = saved
    end

    scenario "failed OmniAuth callback lands back on the SSO landing page" do
      # OmniauthCallbacksController#after_omniauth_failure_path_for has
      # to resolve `new_<scope>_session_path` against the engine's
      # route set. When the host pins helpers via the GLOBAL
      # `Devise.router_name = :admin_panel` (no per-mapping option),
      # `Devise.mappings[scope].router_name` is nil and the handler has
      # to fall back to `Devise.available_router_name` to find the
      # engine proxy — otherwise it tries the helper on the controller
      # itself and raises NoMethodError (500 response → driver
      # exception, not a clean redirect).
      visit "/admin/login"
      click_button ActiveAdmin::Oidc.config.login_button_label

      # Full Capybara assertions: real path + rendered DOM state. If
      # the failure handler had raised, Capybara would never reach the
      # `page` assertions — but we also check the SSO button + flash
      # so a silent redirect to the wrong place can't pass either.
      expect(page).to have_current_path("/admin/login")
      expect(page).to have_button(ActiveAdmin::Oidc.config.login_button_label)
      expect(page).to have_content(ActiveAdmin::Oidc.config.access_denied_message)
    end
  end
end
