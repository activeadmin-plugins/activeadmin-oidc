# frozen_string_literal: true

require "rails_helper"

# Regression spec for the Rails 8 lazy-route-loading bug.
#
# On Rails 8 routes are not drawn at boot — they load lazily on the
# first request. `Devise.mappings` is populated as a side effect of
# drawing routes (every `devise_for :admin_users` call registers a
# mapping). OmniAuth's failure handler walks
# `Devise.mappings.find_by_path!('/admin/auth/oidc', :path)` to figure
# out which scope failed; if the registry is still empty (no request
# has yet caused routes to load) the handler raises:
#
#   Could not find a valid mapping for path "/admin/auth/oidc"
#
# masking the real underlying failure (CSRF, mis-issued id_token, etc).
#
# The engine fixes this with:
#
#   config.after_initialize do
#     Rails.application.routes_reloader.execute_unless_loaded
#   end
#
# (Rails 8 API; on Rails 7.x routes load eagerly so the hook is a no-op.)
RSpec.describe "Rails 8 lazy-route-loading regression" do
  before do
    # Snapshot Devise.mappings so we can restore after simulating the
    # fresh-boot state; clearing it permanently would break other specs.
    @saved_mappings = Devise.mappings.dup
  end

  after do
    Devise.mappings.clear
    @saved_mappings.each { |k, v| Devise.mappings[k] = v }
    Rails.application.routes_reloader.instance_variable_set(:@loaded, true)
  end

  def simulate_fresh_boot_no_routes_drawn!
    Devise.mappings.clear
    Rails.application.routes_reloader.instance_variable_set(:@loaded, false)
  end

  it "the symptom: empty Devise.mappings cannot resolve the OmniAuth callback path" do
    simulate_fresh_boot_no_routes_drawn!

    expect(Devise.mappings).to be_empty
    expect {
      Devise::Mapping.find_by_path!("/admin/auth/oidc", :path)
    }.to raise_error(/Could not find a valid mapping/)
  end

  it "the cure: forcing route load repopulates Devise.mappings before OmniAuth needs it" do
    simulate_fresh_boot_no_routes_drawn!

    # Mirrors the engine's after_initialize hook. `execute_unless_loaded`
    # is Rails 8 only; fall back to `execute` on Rails 7.x so this spec
    # runs on the full CI matrix.
    reloader = Rails.application.routes_reloader
    if reloader.respond_to?(:execute_unless_loaded)
      reloader.execute_unless_loaded
    else
      reloader.execute
    end

    expect(Devise.mappings.keys).to include(:admin_user)
    expect {
      Devise::Mapping.find_by_path!("/admin/auth/oidc", :path)
    }.not_to raise_error
  end
end
