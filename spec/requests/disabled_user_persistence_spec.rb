# frozen_string_literal: true

require "rails_helper"

# Failing spec for HIGH #2 — disabled user persistence.
#
# UserProvisioner#save! runs BEFORE OmniauthCallbacksController#oidc
# checks `active_for_authentication?`. If the on_login hook flips a
# user's `enabled` flag (or any other Devise inactivity guard) and
# returns truthy, the gem still persists the record — only then does
# the controller reject the sign-in. Repeated hostile attempts leave
# a growing pile of provisional AdminUser rows.
#
# Acceptance criterion: a user the host hook marks inactive must NOT
# be persisted to the database.
RSpec.describe "OIDC callback: disabled user not persisted", type: :request do
  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:oidc] = nil

    AdminUser.delete_all
  end

  after { OmniAuth.config.mock_auth[:oidc] = nil }

  def build_auth_hash(uid:, email:)
    OmniAuth::AuthHash.new(
      provider: "oidc",
      uid:      uid,
      info:     { "email" => email, "name" => "Mallory" },
      extra:    { "raw_info" => { "sub" => uid, "email" => email } }
    )
  end

  it "does NOT persist a row when on_login sets enabled=false and returns truthy" do
    ActiveAdmin::Oidc.configure do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = lambda do |admin_user, _claims|
        admin_user.enabled = false
        true # truthy → current code persists the row
      end
    end

    OmniAuth.config.mock_auth[:oidc] =
      build_auth_hash(uid: "mallory-sub", email: "mallory@example.com")

    expect {
      post "/admin/auth/oidc"
      follow_redirect! if response.redirect?
    }.not_to change(AdminUser, :count),
      "disabled-by-hook user was persisted to AdminUser — repeated attempts grow the table"
  end

  it "still redirects the disabled user to the login page" do
    ActiveAdmin::Oidc.configure do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = lambda do |admin_user, _claims|
        admin_user.enabled = false
        true
      end
    end

    OmniAuth.config.mock_auth[:oidc] =
      build_auth_hash(uid: "mallory-sub", email: "mallory@example.com")

    post "/admin/auth/oidc"
    follow_redirect! if response.redirect?

    expect(response).to redirect_to("/admin/login")
  end
end
