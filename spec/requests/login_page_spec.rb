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

  # Active Admin renders its dark mode toggle only in the signed-in top
  # bar, so the login page carries its own. The logged out layout already
  # loads the JS that delegates clicks on `.dark-mode-toggle`, so the
  # markup is the whole feature -- and losing it is silent.
  describe "the dark mode toggle" do
    it "renders on AA v4" do
      skip "AA v3 has no dark mode" unless ActiveAdmin::Oidc.aa_v4?

      get "/admin/login"

      expect(response.body).to include("dark-mode-toggle")
      expect(response.body).to match(/aria-label="[^"]+"[^>]*>/)
    end

    it "is not rendered on AA v3" do
      skip "AA v4 branch renders the toggle" if ActiveAdmin::Oidc.aa_v4?

      get "/admin/login"

      expect(response.body).not_to include("dark-mode-toggle")
    end
  end

  # Regression: AA v3's formtastic stylesheet targets
  # `#login input[type="submit"]`, so a <button type="submit"> stays
  # unstyled (defaults to the dark browser/AA button). Switching to
  # button_to in the AA v3 branch silently regresses the themed blue
  # SSO button to a dark default. Lock the v3 view to submit_tag.
  it "renders the SSO button as an <input type=submit> on AA v3" do
    skip "AA v4+ branch uses button_to with Tailwind classes" if ActiveAdmin::Oidc.aa_v4?

    get "/admin/login"

    expect(response.body).to match(/<input[^>]+type="submit"[^>]+value="[^"]*SSO[^"]*"/)
    expect(response.body).not_to match(/<button[^>]+type="submit"/)
  end
end
