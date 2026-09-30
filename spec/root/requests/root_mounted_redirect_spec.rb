# frozen_string_literal: true

require "root_rails_helper"

# Regression suite for hosts that mount ActiveAdmin at `/` via
# `config.default_namespace = false` (see spec/dummy_root/).
#
# After a successful SSO round-trip the gem has to land the user on the
# ActiveAdmin namespace root. When Devise has a stored location that is
# used, and the bug is invisible. When it does not — every sign-in that
# did not start from a protected page: a bookmarked login page, a session
# cookie rotated during the IdP round-trip — the fallback fires, and a
# fallback that assumes `/admin` sends these hosts to a path that does
# not exist.
RSpec.describe "SSO sign-in on a host mounted at /", type: :request do
  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new(
      provider: "oidc",
      uid:      "sub-root",
      info:     { "email" => "root@example.com" },
      extra:    { "raw_info" => { "sub" => "sub-root", "email" => "root@example.com" } }
    )

    ActiveAdmin::Oidc.configure do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = ->(_admin_user, _claims) { true }
    end

    AdminUser.delete_all
  end

  after { OmniAuth.config.mock_auth[:oidc] = nil }

  # POST the OmniAuth request phase and follow it into the callback, so
  # `response` ends up on whatever the gem's controller redirected to.
  def sign_in_via_sso
    post "/admin/auth/oidc"
    follow_redirect!
  end

  describe "the dummy host itself" do
    it "mounts ActiveAdmin at / and has no /admin" do
      expect(ActiveAdmin.application.default_namespace).to be(false)
      expect(Rails.application.routes.recognize_path("/")).to include(action: "index")
      expect {
        Rails.application.routes.recognize_path("/admin")
      }.to raise_error(ActionController::RoutingError)
    end
  end

  context "with no stored location (sign-in did not start from a protected page)" do
    it "redirects to /" do
      sign_in_via_sso

      expect(response).to be_redirect
      expect(URI(response.location).path).to eq("/")
    end

    it "lands on a page that actually exists" do
      sign_in_via_sso
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dashboard")
    end
  end

  context "with a stored location (bounced off a protected page)" do
    it "returns to where the user was headed" do
      get "/" # unauthenticated → Devise stores admin_user_return_to
      expect(response).to be_redirect

      sign_in_via_sso

      expect(URI(response.location).path).to eq("/")
    end
  end
end
