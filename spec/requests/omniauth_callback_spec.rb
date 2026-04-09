# frozen_string_literal: true

require "rails_helper"

# BDD-style request spec for the OIDC callback flow. Exercises the real
# Devise + OmniAuth + ActiveAdmin + engine stack via the dummy Rails app.
#
# OmniAuth test mode short-circuits the IdP roundtrip: POST /admin/auth/oidc
# immediately invokes the callback action with the mocked auth hash.
RSpec.describe "OIDC callback", type: :request do
  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:oidc] = nil

    ActiveAdmin::Oidc.configure do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = ->(admin_user, _claims) { true }
    end

    AdminUser.delete_all
  end

  after do
    OmniAuth.config.mock_auth[:oidc] = nil
  end

  def build_auth_hash(uid:, email:, extra: {})
    OmniAuth::AuthHash.new(
      provider: "oidc",
      uid:      uid,
      info:     { "email" => email, "name" => "Alice" },
      extra:    { "raw_info" => { "sub" => uid, "email" => email }.merge(extra) }
    )
  end

  # Drive the full OmniAuth handshake: POST /admin/auth/oidc → 302 to
  # /admin/auth/oidc/callback → the gem's callbacks controller runs.
  # Leaves `response` pointed at the controller's own redirect (to the
  # signed-in landing page or the login page on failure).
  def trigger_callback
    post "/admin/auth/oidc"
    follow_redirect! if response.redirect?
  end

  context "new user, on_login hook accepts" do
    it "creates the AdminUser, signs it in, and stores the raw OIDC info" do
      OmniAuth.config.mock_auth[:oidc] =
        build_auth_hash(uid: "sub-new", email: "new@example.com")

      expect {
        trigger_callback
      }.to change(AdminUser, :count).by(1)

      user = AdminUser.find_by(provider: "oidc", uid: "sub-new")
      expect(user).not_to be_nil
      expect(user.email).to eq("new@example.com")
      expect(user.oidc_raw_info).to include("sub" => "sub-new", "email" => "new@example.com")

      expect(response).to be_redirect
    end

    it "redirects directly to the ActiveAdmin namespace root, not the host app's /" do
      OmniAuth.config.mock_auth[:oidc] =
        build_auth_hash(uid: "sub-new", email: "new@example.com")

      post "/admin/auth/oidc"
      follow_redirect! # OmniAuth request phase -> callback
      # `response` is now whatever the callbacks controller redirected to.
      expect(response).to be_redirect
      expect(URI(response.location).path).to eq("/admin")
    end
  end

  context "existing user matched by (provider, uid)" do
    it "signs in without creating a new record" do
      AdminUser.create!(
        email:    "alice@example.com",
        provider: "oidc",
        uid:      "sub-existing"
      )

      OmniAuth.config.mock_auth[:oidc] =
        build_auth_hash(uid: "sub-existing", email: "alice@example.com")

      expect {
        trigger_callback
      }.not_to change(AdminUser, :count)

      expect(response).to be_redirect
    end
  end

  context "existing user matched by identity_attribute (email) with no provider/uid yet" do
    it "migrates the record in place and signs it in" do
      legacy = AdminUser.create!(email: "legacy@example.com")

      OmniAuth.config.mock_auth[:oidc] =
        build_auth_hash(uid: "sub-legacy", email: "legacy@example.com")

      expect {
        trigger_callback
      }.not_to change(AdminUser, :count)

      legacy.reload
      expect(legacy.provider).to eq("oidc")
      expect(legacy.uid).to eq("sub-legacy")
      expect(response).to be_redirect
    end
  end

  context "on_login hook denies the user" do
    before do
      ActiveAdmin::Oidc.config.on_login = ->(_admin_user, _claims) { false }
    end

    it "does not persist the user, redirects to the login page, and sets the access-denied flash" do
      OmniAuth.config.mock_auth[:oidc] =
        build_auth_hash(uid: "sub-denied", email: "denied@example.com")

      expect {
        trigger_callback
      }.not_to change(AdminUser, :count)

      expect(response).to redirect_to("/admin/login")
      expect(flash[:alert]).to eq(ActiveAdmin::Oidc.config.access_denied_message)
    end
  end

  context "misbehaving strategy returns non-Hash raw_info" do
    # Defensive: a custom or buggy OIDC strategy could set
    # auth.extra.raw_info to a String (or nil, Array, etc) instead of
    # the expected Hash of claims. The controller must not crash with
    # a NoMethodError/TypeError — it should fall back to building
    # claims from auth.uid and auth.info["email"] and proceed normally.
    it "falls back to top-level auth fields and still provisions the user" do
      OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new(
        provider: "oidc",
        uid:      "sub-nohash",
        info:     { "email" => "nohash@example.com", "name" => "No Hash" },
        extra:    { "raw_info" => "this-should-be-a-hash-but-isnt" }
      )

      expect { trigger_callback }.to change(AdminUser, :count).by(1)

      user = AdminUser.find_by(provider: "oidc", uid: "sub-nohash")
      expect(user).not_to be_nil
      expect(user.email).to eq("nohash@example.com")
    end
  end

  context "OmniAuth strategy failure (e.g. invalid_credentials)" do
    before do
      OmniAuth.config.mock_auth[:oidc] = :invalid_credentials
    end

    it "lands on the failure action, redirects to login, and shows the access-denied flash" do
      trigger_callback

      expect(response).to redirect_to("/admin/login")
      expect(flash[:alert]).to eq(ActiveAdmin::Oidc.config.access_denied_message)
    end
  end
end
