# frozen_string_literal: true

require "spec_helper"
require_relative "_active_record_setup"

# Failing specs for the HIGH-priority production risks the code review
# surfaced. Each example here is RED today; flipping it green is the
# acceptance criterion for the corresponding fix.
RSpec.describe "UserProvisioner — HIGH-risk regressions" do
  let(:config) do
    ActiveAdmin::Oidc::Configuration.new.tap do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = ->(_user, _claims) { true }
    end
  end

  let(:provider) { "oidc" }
  let(:uid)      { "sub-123" }
  let(:email)    { "alice@example.com" }

  let(:claims) do
    { "sub" => uid, "email" => email, "name" => "Alice" }
  end

  before { AdminUser.delete_all }

  subject(:provisioner) { ActiveAdmin::Oidc::UserProvisioner.new(config, claims: claims, provider: provider) }

  # -------------------------------------------------------------------
  # HIGH #1 — concurrent JIT provisioning re-runs on_login
  # -------------------------------------------------------------------
  # Two simultaneous first sign-ins for the same (provider, uid):
  # the losing thread hits RecordNotUnique, the provisioner retries,
  # finds the now-persisted row, and runs `on_login` AGAIN. Any
  # non-idempotent side effects in the host's hook (audit log row,
  # webhook, email) double-fire.
  describe "concurrent first sign-in race" do
    it "does NOT invoke on_login twice when RecordNotUnique triggers a retry" do
      call_count = 0
      config.on_login = lambda do |_user, _claims|
        call_count += 1
        true
      end

      # Simulate the race: the first save! raises RecordNotUnique (as
      # if the other thread won the insert), and that other thread's
      # row is now visible to find_by on retry.
      raise_once = true
      allow_any_instance_of(AdminUser).to receive(:save!).and_wrap_original do |original, *args|
        if raise_once
          raise_once = false
          # The "other thread" inserted concurrently.
          AdminUser.create!(provider: provider, uid: uid, email: email)
          raise ActiveRecord::RecordNotUnique, "duplicate (provider, uid)"
        else
          original.call(*args)
        end
      end

      provisioner.call

      expect(call_count).to eq(1),
        "on_login was invoked #{call_count}x — host hook side effects would double-fire"
    end
  end

  # -------------------------------------------------------------------
  # HIGH #3 — identity-claim adoption without email_verified
  # -------------------------------------------------------------------
  # A pre-existing AdminUser row with the configured identity_attribute
  # set (e.g. seeded "ceo@example.com") and no (provider, uid) yet is
  # adopted by anyone the IdP says owns that email. When the IdP allows
  # unverified emails (guest/external tenants), an attacker who
  # registers `ceo@example.com` at the IdP takes over the row.
  describe "identity adoption guarded by email_verified" do
    let!(:legacy_admin) do
      AdminUser.create!(email: "ceo@example.com", provider: nil, uid: nil)
    end

    let(:unverified_claims) do
      {
        "sub"            => "attacker-sub",
        "email"          => "ceo@example.com",
        "email_verified" => false
      }
    end

    subject(:attacker_provisioner) do
      ActiveAdmin::Oidc::UserProvisioner.new(config, claims: unverified_claims, provider: provider)
    end

    it "refuses to adopt the legacy row when the email claim is not verified" do
      expect { attacker_provisioner.call }
        .to raise_error(ActiveAdmin::Oidc::ProvisioningError, /verified|adoption/i)
    end

    it "does NOT link the legacy row to the attacker's (provider, uid)" do
      attacker_provisioner.call rescue nil

      legacy_admin.reload
      expect(legacy_admin.provider).to be_nil
      expect(legacy_admin.uid).to be_nil
    end
  end
end
