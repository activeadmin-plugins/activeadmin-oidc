# frozen_string_literal: true

require "rails_helper"

# Cross-cutting security checklist from docs/TEST_PLAN.md §8. Most
# protocol-level checks (state, nonce, alg, iss/aud, exp, jwks) are
# delegated to omniauth_openid_connect and only their *failure-path*
# behavior is verified here — we care that a bad token ends in the
# gem's denial flow, not that we re-implement JWT verification.
RSpec.describe "Security posture", type: :request do
  describe "log filter_parameters" do
    # A gem that ships an OAuth flow and doesn't filter the tokens
    # out of the Rails log is a liability — a crash mid-callback will
    # dump the whole params hash (including `code`, `id_token`,
    # `access_token`, `refresh_token`) straight into production logs.
    #
    # Note: once Rails has served a request, filter_parameters is
    # compiled into a single combined regex (e.g.
    #   "(?-mix:(?i:code)|(?i:id_token)|(?i:access_token)|...)"
    # ), so we stringify the collection and look for each key in it
    # rather than asserting on discrete symbol entries.
    it "includes the OIDC token/code/state/nonce keys so they never end up in Rails logs" do
      filters_str = Rails.application.config.filter_parameters.map(&:to_s).join(" ")

      %w[code id_token access_token refresh_token state nonce].each do |key|
        expect(filters_str).to include(key),
          "expected filter_parameters to filter #{key.inspect}, got: #{filters_str}"
      end
    end
  end

  describe "oidc_raw_info persistence" do
    include ActiveAdmin::Oidc
    let(:config) { ActiveAdmin::Oidc::Configuration.new }

    before do
      config.issuer    = "https://idp.example.com"
      config.client_id = "client-abc"
      config.on_login  = ->(*) { true }
      AdminUser.delete_all
    end

    # Defense in depth: even if the host app's `on_login` somehow
    # pulls `access_token` into claims, UserProvisioner strips it
    # before writing oidc_raw_info. A stolen DB dump must never yield
    # usable bearer tokens.
    it "never persists access_token or refresh_token into oidc_raw_info" do
      provisioner = ActiveAdmin::Oidc::UserProvisioner.new(
        config,
        claims: {
          "sub"           => "sub-999",
          "email"         => "safe@example.com",
          "access_token"  => "secret-bearer",
          "refresh_token" => "secret-refresh",
          "id_token"      => "should-not-persist"
        },
        provider: "oidc"
      )

      admin_user = provisioner.call

      expect(admin_user.oidc_raw_info).to include("sub" => "sub-999", "email" => "safe@example.com")
      expect(admin_user.oidc_raw_info).not_to have_key("access_token")
      expect(admin_user.oidc_raw_info).not_to have_key("refresh_token")
      expect(admin_user.oidc_raw_info).not_to have_key("id_token")
    end
  end

  describe "generic denial message" do
    # Enumeration defense: the user-facing flash must NOT reveal which
    # specific failure happened (unknown user vs. missing claim vs.
    # on_login falsy). Everything funnels into
    # `config.access_denied_message`.
    let(:generic) { "Your account has no permission to access this admin panel." }

    before do
      ActiveAdmin::Oidc.configure do |c|
        c.issuer                = "https://idp.example.com"
        c.client_id             = "client-abc"
        c.access_denied_message = generic
      end
      AdminUser.delete_all
      OmniAuth.config.mock_auth[:oidc] = nil
    end

    after do
      OmniAuth.config.mock_auth[:oidc] = nil
      ActiveAdmin::Oidc.config.reset!
    end

    it "renders the same flash whether on_login returns false or a claim is missing" do
      # Case 1: on_login returns false
      ActiveAdmin::Oidc.config.on_login = ->(*) { false }
      OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new(
        provider: "oidc",
        uid:      "sub-1",
        info:     { email: "u@example.com" },
        extra:    { raw_info: { "sub" => "sub-1", "email" => "u@example.com" } }
      )
      post "/admin/auth/oidc"
      follow_redirect!
      denial_flash_1 = flash[:alert]

      # Case 2: missing identity claim
      ActiveAdmin::Oidc.config.on_login = ->(*) { true }
      OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new(
        provider: "oidc",
        uid:      "sub-2",
        info:     {},
        extra:    { raw_info: { "sub" => "sub-2" } }
      )
      post "/admin/auth/oidc"
      follow_redirect!
      denial_flash_2 = flash[:alert]

      expect(denial_flash_1).to eq(generic)
      expect(denial_flash_2).to eq(generic)
    end
  end
end
