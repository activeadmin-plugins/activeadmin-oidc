# frozen_string_literal: true

require "rails_helper"

# The gem replaces ActiveAdmin's stock email/password login page with an
# SSO-only button. This spec verifies the view override is picked up
# through the engine's view path and that the button label is sourced
# from configuration.
RSpec.describe "Login page", type: :request do
  before do
    ActiveAdmin::Oidc.configure do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = ->(*) { true }
    end
  end

  it "renders the SSO button with the configured label" do
    ActiveAdmin::Oidc.config.login_button_label = "Sign in with Corporate SSO"

    get "/admin/login"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sign in with Corporate SSO")
    expect(response.body).to include(%(action="/admin/auth/oidc"))
  end

  it "does not render email or password fields" do
    get "/admin/login"

    expect(response.body).not_to match(/name="admin_user\[password\]"/)
    expect(response.body).not_to match(/name="admin_user\[email\]"/)
  end

  it "uses the default login button label when not configured" do
    get "/admin/login"

    expect(response.body).to include(ActiveAdmin::Oidc::Configuration::DEFAULT_LOGIN_BUTTON_LABEL)
  end
end
