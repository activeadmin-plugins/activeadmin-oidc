# frozen_string_literal: true

require "isolated_rails_helper"

# The OmniAuth round trip for an isolated engine mounted at a prefix.
#
# Devise reuses one setting -- `Devise.omniauth_path_prefix` -- both to
# declare its OmniAuth routes and to tell the OmniAuth middleware where
# to listen. Those two are not the same string here: routes declared
# inside AdminPanel::Engine get `/admin` prepended by the mount, while
# the middleware sits in the application's Rack stack and sees the URL
# with `/admin` still on it. Feeding the browser-visible `/admin/auth`
# to both puts the callback route at `/admin/admin/auth/oidc/callback`,
# so the redirect the middleware issues 404s.
#
# The gem therefore drives them separately: `omniauth_route_prefix`
# ('/auth' here) for the route declaration, `omniauth_path_prefix`
# ('/admin/auth', derived) as a per-strategy middleware option.
RSpec.describe "Isolated engine OIDC callback", type: :request do
  before do
    # spec_helper resets the singleton config before every example, so
    # restore the parts the callback action reads at request time.
    ActiveAdmin::Oidc.configure do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = ->(_admin_user, _claims) { true }
    end

    OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new(
      provider: "oidc",
      uid:      "sub-isolated",
      info:     { "email" => "isolated@example.com" },
      extra:    { "raw_info" => { "sub" => "sub-isolated", "email" => "isolated@example.com" } }
    )
    AdminUser.delete_all
  end

  after { OmniAuth.config.mock_auth[:oidc] = nil }

  it "declares the callback route engine-relative so the mount prefix lands it on /admin/auth" do
    paths = AdminPanel::Engine.routes.routes.map { |r| r.path.spec.to_s }
    expect(paths).to include("/auth/oidc/callback(.:format)")
  end

  it "keeps the middleware listening on the browser-visible /admin/auth" do
    post "/admin/auth/oidc"

    expect(response).to redirect_to("http://www.example.com/admin/auth/oidc/callback")
  end

  it "completes the round trip and signs the admin user in" do
    post "/admin/auth/oidc"
    follow_redirect!

    expect(AdminUser.find_by(uid: "sub-isolated")).to be_present
    # Not bounced back to the SSO landing page, which is where every
    # failure path ends up.
    expect(response.headers["Location"]).not_to include("/admin/login")
  end
end
