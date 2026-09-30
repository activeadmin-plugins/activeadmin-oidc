# frozen_string_literal: true

require "rails_helper"

# Where a successful callback lands. The path used to be the literal
# '/admin', which is wrong for any host whose ActiveAdmin is not mounted
# exactly there -- a renamed `config.default_namespace`, or ActiveAdmin
# drawn inside a mounted engine, whose mount prefix is prepended to
# every path it declares. It is now read from ActiveAdmin's own route
# helper.
#
# This dummy app uses the default :admin namespace in the main app, so
# the resolved path and the old hardcoded one coincide; what these specs
# pin down is that the value is *derived* rather than written down.
RSpec.describe "Post-sign-in landing path" do
  let(:admin_user) do
    AdminUser.create!(email: "alice@example.com", provider: "oidc", uid: "sub-123")
  end

  let(:controller) do
    ActiveAdmin::Oidc::Devise::OmniauthCallbacksController.new.tap do |c|
      request = ActionDispatch::TestRequest.create
      request.env["devise.mapping"] = Devise.mappings[:admin_user]
      request.env["rack.session"] = ActionController::TestSession.new
      c.set_request!(request)
      c.set_response!(ActionDispatch::TestResponse.create)
    end
  end

  before { AdminUser.delete_all }

  it "uses ActiveAdmin's namespace root helper" do
    expect(controller.send(:after_sign_in_path_for, admin_user))
      .to eq(Rails.application.routes.url_helpers.admin_root_path)
  end

  it "builds the helper name from ActiveAdmin's configured namespace" do
    allow(ActiveAdmin.application).to receive(:default_namespace).and_return(:backoffice)

    # No :backoffice routes exist here, so stand in for the url-helper
    # proxy the controller resolves through: this pins down that the
    # helper NAME follows the setting, not that the route exists.
    allow(controller).to receive(:main_app)
      .and_return(double("main_app", backoffice_root_path: "/backoffice"))

    expect(controller.send(:after_sign_in_path_for, admin_user)).to eq("/backoffice")
  end

  it "falls back to the namespace prefix when the helper cannot be resolved" do
    allow(ActiveAdmin.application).to receive(:default_namespace).and_return(:nowhere)

    expect(controller.send(:after_sign_in_path_for, admin_user)).to eq("/nowhere")
  end

  # ActiveAdmin's root namespace has no prefix at all, so the fallback
  # has to name a real path rather than the empty string, which would
  # render an unredirectable Location header.
  it "falls back to / for ActiveAdmin's root namespace" do
    allow(ActiveAdmin.application).to receive(:default_namespace).and_return(false)

    expect(controller.send(:after_sign_in_path_for, admin_user)).to eq("/")
  end

  it "still honours a stored location" do
    controller.session["admin_user_return_to"] = "/admin/admin_users"

    expect(controller.send(:after_sign_in_path_for, admin_user)).to eq("/admin/admin_users")
  end
end
