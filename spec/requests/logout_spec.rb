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

  # The mounted route should accept whichever HTTP method
  # `ActiveAdmin.application.logout_link_method` is set to, mirroring
  # what AA's own Devise integration does in
  # `lib/active_admin/devise.rb`:
  #
  #   sign_out_via: [*::Devise.sign_out_via, ActiveAdmin.application.logout_link_method].uniq
  #
  # Hardcoding DELETE-only meant AA hosts that kept AA's default
  # `logout_link_method = :get` (the vast majority) 404'd on every
  # Sign Out click: the rendered `<a data-method="get">` link goes
  # through rails-ujs and lands on a route the gem never mounted for
  # GET.
  context "with AA's default logout_link_method (:get)" do
    before { sign_in admin_user }

    it "accepts GET /admin/logout", skip: (ActiveAdmin::Oidc.aa_v4? && "AA 4 dropped logout_link_method; layout uses button_to + Turbo") do
      get "/admin/logout"

      expect(response).to be_redirect

      get "/admin"
      expect(response).to redirect_to("/admin/login")
    end
  end

  # Route-table introspection so a future regression in the mount-time
  # method-resolution logic is caught even if no request spec happens
  # to exercise the affected verb. Reads the verbs actually advertised
  # by the destroy route and compares them against what AA and Devise
  # configured.
  describe "destroy_admin_user_session route verbs" do
    subject(:route) do
      Rails.application.routes.routes.find { |r| r.name == "destroy_admin_user_session" }
    end

    it "exists" do
      expect(route).not_to be_nil
    end

    it "includes Devise.sign_out_via" do
      Array(::Devise.sign_out_via).each do |method|
        expect(route.verb).to match(/#{method.to_s.upcase}/),
          "destroy_admin_user_session does not accept #{method.to_s.upcase} (verb: #{route.verb.inspect})"
      end
    end

    it "includes ActiveAdmin.application.logout_link_method when AA exposes it" do
      aa_app = ::ActiveAdmin.application
      skip "AA 4 dropped logout_link_method" unless aa_app.respond_to?(:logout_link_method)

      expected = aa_app.logout_link_method&.to_s&.upcase
      skip "logout_link_method not set" if expected.nil?

      expect(route.verb).to match(/#{expected}/),
        "destroy_admin_user_session does not accept #{expected} (verb: #{route.verb.inspect})"
    end

    # End-to-end proof that the gem follows host overrides: change
    # AA's setting, reload routes, then drive an actual request
    # through the freshly-drawn route. Catches regressions where
    # logout_link_method gets read once at boot and frozen into the
    # closure (route introspection alone wouldn't catch a frozen
    # `via:` array if Rails resolved it before the stub took effect).
    %i[get post put delete].each do |method|
      it "logs the user out when logout_link_method = #{method.inspect}" do
        aa_app = ::ActiveAdmin.application
        skip "AA 4 dropped logout_link_method" unless aa_app.respond_to?(:logout_link_method)

        original = aa_app.logout_link_method
        begin
          allow(aa_app).to receive(:logout_link_method).and_return(method)
          Rails.application.reload_routes!

          sign_in admin_user
          public_send(method, "/admin/logout")
          expect(response).to be_redirect

          # Session is really cleared — subsequent admin request is
          # bounced back to the login page.
          get "/admin"
          expect(response).to redirect_to("/admin/login")
        ensure
          allow(aa_app).to receive(:logout_link_method).and_return(original)
          Rails.application.reload_routes!
        end
      end
    end
  end
end
