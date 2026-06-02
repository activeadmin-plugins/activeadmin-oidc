# frozen_string_literal: true

require "isolated_rails_helper"

# Isolated-engine variant of the engine-mounted Devise scenario.
#
# AdminPanel::Engine uses `isolate_namespace AdminPanel`, mounted at
# `/admin` in main app routes. Inside the engine, devise_for registers
# `:admin_users` pinned to the engine via `router_name: :admin_panel`.
#
# Key difference from non-isolated: paths declared inside the engine
# get prefixed by the mount path, so a route declared as `/admin/login`
# inside the engine would become `/admin/admin/login` after mounting.
# Hosts in this layout must therefore configure
# `ActiveAdmin::Oidc.config.login_path = '/login'` (engine-relative);
# the gem then mounts at the correct effective path.
RSpec.feature "Isolated engine OIDC sessions", type: :feature do
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

  it "the engine's route table contains GET /login (relative — mount prefix added later)" do
    paths = AdminPanel::Engine.routes.routes.map { |r| [r.verb, r.path.spec.to_s] }
    expect(paths).to include(["GET", "/login(.:format)"])
  end

  scenario "Capybara visit to /admin/login (mount prefix + engine-relative path) renders the SSO landing page" do
    visit "/admin/login"
    expect(page.status_code).to eq(200)
    expect(page.body).to include(ActiveAdmin::Oidc.config.login_button_label)
  end

  context "OmniAuth failure path" do
    around do |ex|
      saved = OmniAuth.config.mock_auth[:oidc]
      OmniAuth.config.mock_auth[:oidc] = :invalid_credentials
      ex.run
      OmniAuth.config.mock_auth[:oidc] = saved
    end

    scenario "failed OmniAuth callback lands back on the SSO landing page" do
      # As in the non-isolated case, the failure handler must resolve
      # the session helper through the engine — and via the isolated
      # engine's mount prefix the effective path stays `/admin/login`
      # because `config.login_path = '/login'` is engine-relative.
      visit "/admin/login"
      click_button ActiveAdmin::Oidc.config.login_button_label
      expect(page).to have_current_path("/admin/login")
    end
  end
end
