# frozen_string_literal: true

require "rails_helper"

# Regression spec for MEDIUM #4 — login view must derive the OmniAuth
# callback path from `OmniAuth.config.path_prefix`, not hardcode it.
#
# `app/views/active_admin/devise/sessions/new.html.erb` used to hardcode
# `"/admin/auth/oidc"` in the form action. Hosts that customise
# `Devise.omniauth_path_prefix` (mount Devise at a non-`/admin` path,
# or use a different sub-prefix for SSO) ended up with a button POSTing
# to a dead URL — the gem's strategy is registered at the configured
# prefix, not the hardcoded one.
#
# We can't use Devise's `omniauth_authorize_path` helper here because
# the OmniAuth middleware lives at the Rack level (global path prefix),
# while Devise route helpers resolve through the engine and get
# re-prefixed by the engine mount — producing e.g. `/admin/admin/auth/oidc`
# when Devise is engine-mounted. `OmniAuth.config.path_prefix` is the
# single source of truth for where the middleware actually listens.
RSpec.describe "Login view OmniAuth path", type: :request do
  before do
    ActiveAdmin::Oidc.configure do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = ->(*) { true }
    end

    # Force routes to load NOW. Otherwise Rails 8 lazy loading defers
    # `devise_for` until the first request — at which point the stub
    # below is active, Devise's "OmniAuth.config.path_prefix matches
    # Devise.omniauth_path_prefix" guard sees the sentinel, and raises.
    # `execute_unless_loaded` is Rails 8+; fall back for 7.x.
    reloader = Rails.application.routes_reloader
    if reloader.respond_to?(:execute_unless_loaded)
      reloader.execute_unless_loaded
    else
      Rails.application.reload_routes!
    end
  end

  it "renders the form action from OmniAuth.config.path_prefix (no hardcoded literal)" do
    # Stub the OmniAuth path prefix to a sentinel value the hardcoded
    # string could never match. If the view actually reads the prefix,
    # the rendered form action will be `<sentinel>/oidc`; if it
    # hardcodes the path, the literal "/admin/auth/oidc" stays.
    sentinel = "/sentinel-omniauth-prefix"
    allow(OmniAuth.config).to receive(:path_prefix).and_return(sentinel)

    get "/admin/login"

    expect(response.body).to include(%(action="#{sentinel}/oidc")),
      "form action ignores Devise.omniauth_path_prefix — hosts that " \
      "customise the prefix get a button POSTing to a dead URL"
  end
end
