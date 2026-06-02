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
  let(:uid)   { "mallory-sub" }
  let(:email) { "mallory@example.com" }
  let(:auth_hash) do
    OmniAuth::AuthHash.new(
      provider: "oidc",
      uid:      uid,
      info:     { "email" => email, "name" => "Mallory" },
      extra:    { "raw_info" => { "sub" => uid, "email" => email } }
    )
  end

  let(:disabling_hook) do
    lambda do |admin_user, _claims|
      admin_user.enabled = false
      true # truthy → pre-fix code persisted the row
    end
  end

  let(:noop_hook) { ->(*) { true } }

  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:oidc] = nil
    AdminUser.delete_all

    ActiveAdmin::Oidc.configure do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = disabling_hook
    end

    OmniAuth.config.mock_auth[:oidc] = auth_hash
  end

  after { OmniAuth.config.mock_auth[:oidc] = nil }

  def post_callback
    post "#{OmniAuth.config.path_prefix}/oidc"
    follow_redirect! if response.redirect?
  end

  it "does NOT persist a row when on_login sets enabled=false and returns truthy" do
    expect { post_callback }.not_to change(AdminUser, :count),
      "disabled-by-hook user was persisted to AdminUser — repeated attempts grow the table"
  end

  it "still redirects the disabled user to the login page" do
    post_callback
    expect(response).to redirect_to(new_admin_user_session_path)
  end

  # Code-review followup: the original retry short-circuit
  # (`return admin_user if @retried`) skipped the
  # `active_for_authentication?` guard. If a host-side trigger
  # flips the winner's row to inactive between the concurrent
  # insert and our retry read, the loser thread used to sign in
  # silently. Enforce the same Devise inactivity guard on the
  # retry leg.
  it "rejects an inactive winner row on the retry leg" do
    ActiveAdmin::Oidc.config.on_login = noop_hook

    # First save! simulates a lost race: the "other thread" inserts
    # the row as ACTIVE, then a host-side trigger flips it inactive
    # before our retry read. RecordNotUnique sends us through the
    # retry path, where find_by(provider, uid) returns the now-
    # inactive row.
    raise_once = true
    allow_any_instance_of(AdminUser).to receive(:save!).and_wrap_original do |original, *args|
      if raise_once
        raise_once = false
        winner = AdminUser.create!(provider: "oidc", uid: uid, email: email)
        winner.update_column(:enabled, false)
        raise ActiveRecord::RecordNotUnique, "duplicate (provider, uid)"
      else
        original.call(*args)
      end
    end

    post_callback

    expect(response).to redirect_to(new_admin_user_session_path)
    # Tighter than the redirect check: confirm the inactive winner
    # did NOT end up in the Warden session. If they did, subsequent
    # protected pages would honor the session until the next
    # active_for_authentication? check, and the user would briefly
    # appear signed-in.
    expect(session.to_h.keys.grep(/warden/i)).to be_empty,
      "retry leg signed in an inactive winner row — active_for_authentication? was skipped"
  end

  # The HIGH #2 fix raised ProvisioningError when the hook flipped
  # the inactivity flag, but the controller's generic rescue replaced
  # the model's I18n-translated inactive_message with the generic
  # access_denied_message. The disabled user lost the specific reason
  # ("Your account has not been activated yet") and saw the catch-all
  # denial flash instead. Surface the original reason via a dedicated
  # error class.
  it "shows the model's I18n-translated inactive_message in the flash" do
    post_callback
    expect(flash[:alert]).to eq(I18n.t("devise.failure.inactive")),
      "expected the disabled user to see Devise's translated inactive " \
      "message, but the controller used the generic denial flash"
  end

  # Code-review followup: if a host's inactive_message returns nil
  # (legal Devise return shape — `super` returns :inactive but a
  # subclass may legitimately return nil for other inactivity
  # branches) the InactiveError used to carry "" as its key, which
  # collapsed to I18n.t("devise.failure.") and rendered an empty
  # flash. Default to :inactive so the user always sees a reason.
  it "defaults to :inactive when the model's inactive_message is blank" do
    allow_any_instance_of(AdminUser).to receive(:inactive_message).and_return(nil)
    post_callback
    expect(flash[:alert]).to eq(I18n.t("devise.failure.inactive")),
      "blank inactive_message produced an empty flash"
  end

  # Code-review followup: when the model returns a custom symbol
  # whose translation is missing (e.g. :locked_by_admin with no
  # devise.failure.locked_by_admin key), the controller used to
  # render the raw symbol name to an unauthenticated visitor —
  # leaking host-internal state. Fall back to the standard inactive
  # translation instead.
  it "hides custom inactive_message symbols when the translation is missing" do
    allow_any_instance_of(AdminUser).to receive(:inactive_message).and_return(:locked_by_admin)
    post_callback
    expect(flash[:alert]).not_to include("locked_by_admin"),
      "raw inactive_message symbol leaked into the public flash"
    expect(flash[:alert]).to eq(I18n.t("devise.failure.inactive"))
  end
end
