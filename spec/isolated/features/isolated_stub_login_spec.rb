# frozen_string_literal: true

require "isolated_rails_helper"

# Stub login inside an isolated engine. The route is declared as
# "#{config.login_path}/stub", so with the engine-relative
# `login_path = '/login'` this host must configure, the effective URL
# after the `mount AdminPanel::Engine => '/admin'` prefix is
# `/admin/login/stub`. A hardcoded '/admin/login/stub' in the gem would
# become '/admin/admin/login/stub' here.
RSpec.feature "Isolated engine stub login", type: :feature do
  before do
    # spec_helper resets the gem config before every example, which
    # wipes the engine-relative login_path the dummy app's initializer
    # set. Restore it before redrawing routes.
    ActiveAdmin::Oidc.configure do |c|
      c.login_path         = "/login"
      c.logout_path        = "/logout"
      c.on_login           = ->(*) { true }
      c.stub_login_enabled = true
      c.stub_login_claims  = { "sub" => "stub-iso", "email" => "iso@example.com" }
    end
    Rails.application.reload_routes!
    AdminUser.delete_all
  end

  after do
    ActiveAdmin::Oidc.reset!
    Rails.application.reload_routes!
  end

  it "declares the stub route engine-relative" do
    paths = AdminPanel::Engine.routes.routes.map { |r| [r.verb, r.path.spec.to_s] }
    expect(paths).to include(["POST", "/login/stub(.:format)"])
  end

  scenario "the login page's stub button signs in through the mount prefix" do
    visit "/admin/login"
    expect(page.body).to include(%(action="/admin/login/stub"))
    expect(page.body).to include(ActiveAdmin::Oidc.config.stub_login_button_label)

    # Driven without following the redirect: on success the gem sends the
    # user to a hardcoded /admin, which this dummy app (ActiveAdmin lives
    # inside the mounted engine) does not route.
    page.driver.browser.process(:post, "/admin/login/stub")

    expect(page.driver.browser.last_response.status).to eq(302)
    expect(AdminUser.find_by(email: "iso@example.com")).not_to be_nil
  end
end
