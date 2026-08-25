# frozen_string_literal: true

require "rails_helper"

# Regression spec for MEDIUM #4 — the login view must derive the OmniAuth
# request path from configuration, not hardcode `/admin/auth/oidc`. Hosts
# that rename ActiveAdmin's namespace, or set `omniauth_path_prefix`
# explicitly, otherwise get a button POSTing to a dead URL.
#
# The source of truth is `ActiveAdmin::Oidc.config.omniauth_path_prefix`:
# the browser-visible path the OmniAuth middleware listens on. Neither
# `Devise.omniauth_path_prefix` nor `OmniAuth.config.path_prefix` works
# here — Devise sets both to the prefix it *declares its routes* with,
# which for an engine-mounted host is the same path minus the engine's
# mount prefix.
RSpec.describe "Login view OmniAuth path", type: :request do
  before do
    ActiveAdmin::Oidc.configure do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = ->(*) { true }
    end
  end

  it "renders the form action from the configured prefix (no hardcoded literal)" do
    # A sentinel the hardcoded string could never match: if the view
    # reads the config, the action is `<sentinel>/oidc`; if it hardcodes
    # the path, the literal "/admin/auth/oidc" stays.
    sentinel = "/sentinel-omniauth-prefix"
    ActiveAdmin::Oidc.config.omniauth_path_prefix = sentinel

    get "/admin/login"

    expect(response.body).to include(%(action="#{sentinel}/oidc")),
      "form action ignores ActiveAdmin::Oidc.config.omniauth_path_prefix — " \
      "hosts that customise the prefix get a button POSTing to a dead URL"
  end
end
