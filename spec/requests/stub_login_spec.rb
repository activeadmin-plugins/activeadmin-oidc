# frozen_string_literal: true

require "rails_helper"

# Stub login is the development escape hatch for machines whose redirect
# URI the IdP does not know: the login page renders as usual, and a
# second button signs in with locally fabricated claims. The point of
# these specs is that the stub goes through the SAME provisioning path
# as a real callback -- on_login, the identity lookup, oidc_raw_info and
# the active_for_authentication? guard all still run.
RSpec.describe "Stub login", type: :request do
  # The route is drawn conditionally on the config flag, so flipping the
  # flag at runtime requires a redraw. The global config reset in
  # spec_helper runs before each example, so undo the redraw afterwards
  # or the route leaks into unrelated specs.
  def enable_stub_login!(claims: nil)
    ActiveAdmin::Oidc.config.stub_login_enabled = true
    ActiveAdmin::Oidc.config.stub_login_claims = claims unless claims.nil?
    Rails.application.reload_routes!
  end

  before do
    ActiveAdmin::Oidc.configure do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = ->(*) { true }
    end

    AdminUser.delete_all
  end

  after do
    ActiveAdmin::Oidc.reset!
    Rails.application.reload_routes!
  end

  describe "the login page" do
    it "renders no stub button or warning when stub login is off" do
      get "/admin/login"

      expect(response.body).not_to include("activeadmin-oidc-stub-login")
      expect(response.body).not_to include("Stub login is enabled")
    end

    it "renders the stub button, the identity it signs in as, and a warning" do
      enable_stub_login!(claims: { "sub" => "stub-1", "email" => "dev@example.com" })

      get "/admin/login"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Stub login is enabled")
      expect(response.body).to include("dev@example.com")
      expect(response.body).to include(
        ActiveAdmin::Oidc::Configuration::DEFAULT_STUB_LOGIN_BUTTON_LABEL
      )
      expect(response.body).to include(%(action="/admin/login/stub"))
    end

    it "still renders the real SSO button alongside the stub one" do
      enable_stub_login!

      get "/admin/login"

      expect(response.body).to include(%(action="/admin/auth/oidc"))
      expect(response.body).to include(%(action="/admin/login/stub"))
    end

    it "hides the SSO button when no IdP is configured at all" do
      ActiveAdmin::Oidc.config.issuer    = nil
      ActiveAdmin::Oidc.config.client_id = nil
      enable_stub_login!

      get "/admin/login"

      expect(response.body).not_to include(%(action="/admin/auth/oidc"))
      expect(response.body).to include(%(action="/admin/login/stub"))
    end
  end

  describe "POST /admin/login/stub" do
    it "is not routable when stub login is disabled" do
      expect { post "/admin/login/stub" }
        .to raise_error(ActionController::RoutingError)
    end

    it "provisions the admin user from the configured claims and signs in" do
      enable_stub_login!(
        claims: { "sub" => "stub-1", "email" => "dev@example.com", "department" => "ops" }
      )

      expect { post "/admin/login/stub" }.to change(AdminUser, :count).by(1)

      user = AdminUser.find_by(email: "dev@example.com")
      expect(user).not_to be_nil
      # provider is the gem's own, never a separate "stub"/"test" value:
      # a row stamped with a different provider could never be matched by
      # a later real SSO login, and would trip the takeover guard.
      expect(user.provider).to eq("oidc")
      expect(user.uid).to eq("stub-1")
      expect(user.oidc_raw_info).to include("sub" => "stub-1", "department" => "ops")

      expect(response).to be_redirect
      expect(URI(response.location).path).to eq("/admin")
    end

    it "reuses the existing row on a second stub login" do
      enable_stub_login!(claims: { "sub" => "stub-1", "email" => "dev@example.com" })

      post "/admin/login/stub"
      expect { post "/admin/login/stub" }.not_to change(AdminUser, :count)
    end

    it "runs the host's on_login hook and honours a denial" do
      called_with = nil
      ActiveAdmin::Oidc.config.on_login = lambda { |_admin_user, claims|
        called_with = claims
        false
      }
      enable_stub_login!(claims: { "sub" => "stub-1", "email" => "dev@example.com" })

      expect { post "/admin/login/stub" }.not_to change(AdminUser, :count)

      expect(called_with).to include("sub" => "stub-1", "email" => "dev@example.com")
      expect(response).to redirect_to("/admin/login")
      follow_redirect!
      expect(response.body).to include(ActiveAdmin::Oidc.config.access_denied_message)
    end

    it "honours active_for_authentication? just like a real callback" do
      ActiveAdmin::Oidc.config.on_login = lambda { |admin_user, _claims|
        admin_user.enabled = false
        true
      }
      enable_stub_login!(claims: { "sub" => "stub-1", "email" => "dev@example.com" })

      expect { post "/admin/login/stub" }.not_to change(AdminUser, :count)
      expect(response).to redirect_to("/admin/login")
    end

    it "accepts a callable so the identity can come from ENV per request" do
      identity = "first@example.com"
      enable_stub_login!(claims: -> { { "sub" => "stub-#{identity}", "email" => identity } })

      post "/admin/login/stub"
      expect(AdminUser.find_by(email: "first@example.com")).not_to be_nil

      identity = "second@example.com"
      post "/admin/login/stub"
      expect(AdminUser.find_by(email: "second@example.com")).not_to be_nil
    end

    it "reports a misconfigured claims hash instead of a generic denial" do
      enable_stub_login!(claims: { "sub" => "stub-1" }) # no identity claim

      post "/admin/login/stub"

      follow_redirect!
      expect(response.body).to include("stub login misconfigured")
      expect(response.body).to include("email")
    end

    it "404s when the flag is flipped off after the route was drawn" do
      enable_stub_login!
      ActiveAdmin::Oidc.config.stub_login_enabled = false

      post "/admin/login/stub"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the production guard" do
    it "refuses to boot when stub login is enabled in production" do
      ActiveAdmin::Oidc.config.stub_login_enabled = true
      allow(Rails).to receive(:env).and_return(
        ActiveSupport::StringInquirer.new("production")
      )

      expect { ActiveAdmin::Oidc::Engine.enforce_stub_login_policy! }
        .to raise_error(ActiveAdmin::Oidc::ConfigurationError, /production/)
    end

    it "raises at boot when a literal claims hash is missing the identity claim" do
      ActiveAdmin::Oidc.config.stub_login_enabled = true
      ActiveAdmin::Oidc.config.stub_login_claims = { "sub" => "stub-1" }

      expect { ActiveAdmin::Oidc::Engine.enforce_stub_login_policy! }
        .to raise_error(ActiveAdmin::Oidc::ConfigurationError, /identity_claim/)
    end

    it "does not evaluate a callable at boot" do
      ActiveAdmin::Oidc.config.stub_login_enabled = true
      ActiveAdmin::Oidc.config.stub_login_claims = -> { raise "must not be called at boot" }

      expect { ActiveAdmin::Oidc::Engine.enforce_stub_login_policy! }.not_to raise_error
    end

    it "is a no-op when stub login is off" do
      expect(ActiveAdmin::Oidc::Engine.enforce_stub_login_policy!).to be(false)
    end
  end
end
