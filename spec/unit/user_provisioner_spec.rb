# frozen_string_literal: true

require "spec_helper"
require_relative "_active_record_setup"

RSpec.describe ActiveAdmin::Oidc::UserProvisioner do
  let(:config) do
    ActiveAdmin::Oidc::Configuration.new.tap do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = ->(admin_user, claims) {
        # default test hook: accept everything, no mutation beyond base fields
        true
      }
    end
  end

  let(:provider) { "oidc" }
  let(:uid)      { "sub-123" }
  let(:email)    { "alice@example.com" }

  let(:claims) do
    {
      "sub"   => uid,
      "email" => email,
      "name"  => "Alice"
    }
  end

  before do
    AdminUser.delete_all
  end

  subject(:provisioner) { described_class.new(config, claims: claims, provider: provider) }

  describe "#call (happy path)" do
    it "creates a new AdminUser when no match exists" do
      expect { provisioner.call }.to change(AdminUser, :count).by(1)
    end

    it "sets provider and uid on the new record" do
      admin = provisioner.call
      expect(admin.provider).to eq(provider)
      expect(admin.uid).to eq(uid)
    end

    it "populates the identity attribute from the identity claim" do
      admin = provisioner.call
      expect(admin.email).to eq(email)
    end

    it "stores id_token claims in oidc_raw_info" do
      admin = provisioner.call
      expect(admin.oidc_raw_info).to include("sub" => uid, "email" => email)
    end

    it "does not persist access_token or refresh_token in oidc_raw_info" do
      c = claims.merge("access_token" => "at", "refresh_token" => "rt")
      admin = described_class.new(config, claims: c, provider: provider).call
      expect(admin.oidc_raw_info).not_to have_key("access_token")
      expect(admin.oidc_raw_info).not_to have_key("refresh_token")
    end
  end

  describe "matching existing records" do
    it "updates an existing record matched on (provider, uid)" do
      existing = AdminUser.create!(email: "old@example.com", provider: provider, uid: uid)
      expect { provisioner.call }.not_to change(AdminUser, :count)
      expect(existing.reload.email).to eq(email)
    end

    it "migrates an existing record matched by identity attribute (no provider/uid yet)" do
      existing = AdminUser.create!(email: email, provider: nil, uid: nil)
      result = provisioner.call
      expect(result.id).to eq(existing.id)
      expect(existing.reload.provider).to eq(provider)
      expect(existing.reload.uid).to eq(uid)
    end

    it "refuses to adopt an identity-matched row already locked to a different uid" do
      AdminUser.create!(email: email, provider: provider, uid: "different-uid")
      expect { provisioner.call }.to raise_error(ActiveAdmin::Oidc::ProvisioningError, /takeover|conflict|identity/i)
    end

    it "uses identity_attribute when not :email" do
      config.identity_attribute = :username
      config.identity_claim     = :preferred_username
      c = { "sub" => uid, "preferred_username" => "alice", "email" => email }

      existing = AdminUser.create!(email: "placeholder@example.com", username: "alice", provider: nil, uid: nil)
      result = described_class.new(config, claims: c, provider: provider).call
      expect(result.id).to eq(existing.id)
      expect(result.username).to eq("alice")
    end
  end

  describe "on_login hook contract" do
    it "calls config.on_login with (admin_user, claims)" do
      seen = nil
      config.on_login = ->(admin_user, claims_arg) {
        seen = [admin_user, claims_arg]
        true
      }
      provisioner.call
      expect(seen[0]).to be_a(AdminUser)
      expect(seen[1]).to eq(claims)
    end

    it "persists mutations the hook makes to arbitrary host columns" do
      config.on_login = ->(admin_user, claims) {
        admin_user.department = claims["department"] || "ops"
        true
      }
      admin = described_class.new(config, claims: claims.merge("department" => "eng"), provider: provider).call
      expect(admin.reload.department).to eq("eng")
    end

    it "raises ProvisioningError with the denial message when the hook returns false" do
      config.on_login = ->(_a, _c) { false }
      expect { provisioner.call }.to raise_error(ActiveAdmin::Oidc::ProvisioningError, config.access_denied_message)
    end

    it "raises ProvisioningError when the hook returns nil" do
      config.on_login = ->(_a, _c) { nil }
      expect { provisioner.call }.to raise_error(ActiveAdmin::Oidc::ProvisioningError)
    end

    it "does not create a new AdminUser when the hook denies" do
      config.on_login = ->(_a, _c) { false }
      expect { provisioner.call rescue nil }.not_to change(AdminUser, :count)
    end

    it "does not mutate an existing AdminUser when the hook denies" do
      existing = AdminUser.create!(email: "old@example.com", provider: provider, uid: uid, department: "eng")
      config.on_login = ->(admin_user, _c) {
        admin_user.department = "should-not-stick"
        false
      }
      provisioner.call rescue nil
      expect(existing.reload.department).to eq("eng")
      expect(existing.reload.email).to eq("old@example.com")
    end

    it "propagates unrelated exceptions from the hook" do
      config.on_login = ->(_a, _c) { raise "boom" }
      expect { provisioner.call }.to raise_error(RuntimeError, "boom")
    end
  end

  describe "malformed claims" do
    it "raises ProvisioningError when sub is blank" do
      c = claims.merge("sub" => "")
      expect { described_class.new(config, claims: c, provider: provider).call }
        .to raise_error(ActiveAdmin::Oidc::ProvisioningError, /sub/i)
    end

    it "raises ProvisioningError when the identity claim is blank" do
      c = claims.merge("email" => "")
      expect { described_class.new(config, claims: c, provider: provider).call }
        .to raise_error(ActiveAdmin::Oidc::ProvisioningError, /email|identity/i)
    end

    it "raises ProvisioningError on ActiveRecord validation errors" do
      config.on_login = ->(admin_user, _c) {
        admin_user.email = nil # fail AdminUser validation
        true
      }
      expect { provisioner.call }.to raise_error(ActiveAdmin::Oidc::ProvisioningError, /email/i)
    end
  end

  describe "concurrent first-login race" do
    it "results in exactly one AdminUser for a given (provider, uid)" do
      # Simulate two callbacks racing: both see no existing row, both try to
      # create. The unique index enforces that only one wins.
      second_config = config.dup
      second_config.on_login = config.on_login

      first = described_class.new(config, claims: claims, provider: provider)
      second = described_class.new(second_config, claims: claims, provider: provider)

      first.call
      expect { second.call }.not_to raise_error
      expect(AdminUser.where(provider: provider, uid: uid).count).to eq(1)
    end
  end
end
