# frozen_string_literal: true

require "rails_helper"

# Verifies that signing out goes through Devise's stock session destroy
# and does NOT hit the IdP's end_session_endpoint. The gem intentionally
# keeps logout local — hosts that want RP-initiated single-logout can
# override the destroy action themselves.
RSpec.describe "Logout", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    ActiveAdmin::Oidc.configure do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = ->(*) { true }
    end

    AdminUser.delete_all
  end

  let!(:admin_user) do
    AdminUser.create!(
      email:    "alice@example.com",
      provider: "oidc",
      uid:      "sub-123"
    )
  end

  context "with a signed-in admin user" do
    before { sign_in admin_user }

    it "clears the session and redirects to the login page" do
      # sanity: we can reach /admin while signed in
      get "/admin"
      expect(response).to have_http_status(:ok).or have_http_status(:redirect)

      delete "/admin/logout"
      expect(response).to be_redirect

      # Subsequent admin request is bounced back to the login page.
      get "/admin"
      expect(response).to redirect_to("/admin/login")
    end

    it "does not hit the IdP end_session endpoint" do
      WebMock.reset!
      stub_any = WebMock.stub_request(:any, /idp\.example\.com/)

      delete "/admin/logout"

      expect(stub_any).not_to have_been_requested
    end
  end

  context "when already signed out" do
    it "is idempotent and still redirects to login" do
      delete "/admin/logout"
      expect(response).to be_redirect

      get "/admin"
      expect(response).to redirect_to("/admin/login")
    end
  end
end
