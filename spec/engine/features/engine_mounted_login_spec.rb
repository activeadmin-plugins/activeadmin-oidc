# frozen_string_literal: true

require "engine_rails_helper"

# Engine-mounted Devise + OIDC scenario:
#
#   - AdminPanel::Engine is a non-isolated Rails engine
#   - `devise_for :admin_users, ..., router_name: :admin_panel` lives
#     inside the engine's routes
#   - `Devise.router_name = :admin_panel` pins Devise's URL helpers to
#     `AdminPanel::Engine.routes`
#
# With AdminUser also OIDC-only (`devise :omniauthable`, no
# `:database_authenticatable`), Devise generates no session routes.
# activeadmin-oidc has to mount `/admin/login` and `/admin/logout`
# *inside the engine's route set*, otherwise
# `AdminPanel::Engine.routes.url_helpers.new_admin_user_session_path`
# stays undefined and host-side failure apps (Devise::FailureApp
# subclasses that redirect via the engine's helpers) blow up with
# NoMethodError.
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
end
