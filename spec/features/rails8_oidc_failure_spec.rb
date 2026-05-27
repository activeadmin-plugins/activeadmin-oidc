# frozen_string_literal: true

require "rails_helper"
require "capybara/rspec"

# End-to-end Capybara spec for the Rails 8 OIDC failure flow.
#
# Regression context: on Rails 8 routes load lazily, and OmniAuth's
# failure handler walks `Devise.mappings.find_by_path!` which is only
# fully populated (with path-aware metadata) once `devise_for` has
# run as part of drawing routes. If a host app's model isn't yet
# autoloaded and routes haven't been drawn, the very first failed
# OIDC callback raises "Could not find a valid mapping for path
# /admin/auth/oidc", masking the real underlying error.
#
# The engine fixes this with
# `config.after_initialize { routes_reloader.execute_unless_loaded }`.
# This spec exercises the failure flow end-to-end on Rails 8 to guard
# against regressions to that path.
#
# Skipped on Rails 7.x where routes load eagerly and
# `execute_unless_loaded` doesn't exist.
RSpec.feature "Rails 8 OIDC failure callback", type: :feature do
  before do
    skip "Rails 8+ only" if Rails::VERSION::MAJOR < 8

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:oidc] = :invalid_credentials
  end

  after { OmniAuth.config.mock_auth[:oidc] = nil }

  scenario "an OIDC strategy failure redirects to /admin/login" do
    visit "/admin/auth/oidc"
    expect(page).to have_current_path("/admin/login")
  end
end
