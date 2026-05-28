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
# subclasses that redirect via the engine's helpers, e.g. pbx-api's
# `PbxDevise#redirect_url`) blow up with NoMethodError.
RSpec.describe "Engine-mounted OIDC sessions" do
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

  it "Rails.application.routes does NOT define the session helpers (they live on the engine)" do
    # Sanity check: if the gem mounted on the wrong route set the
    # helper would appear here instead of on the engine.
    expect(Rails.application.routes.url_helpers).not_to respond_to(:new_admin_user_session_path)
  end
end
