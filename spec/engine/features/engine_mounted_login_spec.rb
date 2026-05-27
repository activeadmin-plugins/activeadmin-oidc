# frozen_string_literal: true

require "engine_rails_helper"

# Engine-mounted Devise + OIDC scenario (pbx-api / yeti-web pattern):
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
# subclasses that redirect via the engine's helpers) blow up.
RSpec.feature "Engine-mounted OIDC login", type: :feature do
  it "AdminPanel::Engine.routes.url_helpers exposes new_admin_user_session_path" do
    expect {
      AdminPanel::Engine.routes.url_helpers.new_admin_user_session_path
    }.not_to raise_error
  end

  scenario "GET /admin/login renders the SSO landing page" do
    visit "/admin/login"
    expect(page.status_code).to eq(200)
    expect(page.body).to include(ActiveAdmin::Oidc.config.login_button_label)
  end
end
