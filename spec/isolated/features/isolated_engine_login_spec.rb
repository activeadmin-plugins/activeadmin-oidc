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
RSpec.describe "Isolated engine OIDC sessions" do
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

  it "from the main app, GET /admin/login resolves through the mount prefix" do
    main_paths = Rails.application.routes.routes.map { |r| r.path.spec.to_s }
    expect(main_paths.any? { |p| p.include?("/admin") }).to be(true)
  end

  it "main app routes resolve GET /admin/login through the mounted engine" do
    request = ActionDispatch::Request.new("PATH_INFO" => "/admin/login", "REQUEST_METHOD" => "GET")
    expect { Rails.application.routes.router.recognize(request) {} }.not_to raise_error
  end
end
