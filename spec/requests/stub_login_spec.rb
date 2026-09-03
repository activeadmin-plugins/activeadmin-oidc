# frozen_string_literal: true

require "rails_helper"

# Stub login is the development escape hatch for machines whose redirect
# URI the IdP does not know: the login page renders as usual, and its
# button signs in with locally fabricated claims. The point of these
# specs is that the stub goes through the SAME provisioning path as a
# real callback -- on_login, the identity lookup, oidc_raw_info and the
# active_for_authentication? guard all still run.
RSpec.describe "Stub login", type: :request do
  # `stub_dev_env_login!` is a no-op outside the development environment,
  # and these specs run in the test environment. Stub the two readers it
  # would have set instead of pretending to be development.
  #
  # The route is drawn conditionally on the flag, so turning it on at
  # runtime requires a redraw. Undo the redraw afterwards or the route
  # leaks into unrelated specs.
  def enable_stub_login!(&claims_block)
    allow(ActiveAdmin::Oidc.config)
      .to receive(:stub_dev_env_login_enabled?).and_return(true)
    allow(ActiveAdmin::Oidc.config)
      .to receive(:stub_dev_env_login_claims_block).and_return(claims_block)
    Rails.application.reload_routes!
  end

  before do
    ActiveAdmin::Oidc.configure do |c|
      c.issuer    = "https://idp.example.com"
      c.client_id = "client-abc"
      c.on_login  = ->(*) { true }
    end

    AdminUser.delete_all
  end

  after do
    ActiveAdmin::Oidc.reset!
    Rails.application.reload_routes!
  end

  describe "the config API" do
    it "refuses to enable outside the development environment" do
      expect(ActiveAdmin::Oidc.config.stub_dev_env_login!).to be(false)
      expect(ActiveAdmin::Oidc.config.stub_dev_env_login_enabled?).to be(false)
    end

    it "enables and stores the claims block in the development environment" do
      allow(Rails).to receive(:env).and_return(
        ActiveSupport::StringInquirer.new("development")
      )
      block = ->(claims) { claims }

      expect(ActiveAdmin::Oidc.config.stub_dev_env_login!(&block)).to be(true)
      expect(ActiveAdmin::Oidc.config.stub_dev_env_login_enabled?).to be(true)
      expect(ActiveAdmin::Oidc.config.stub_dev_env_login_claims_block).to be(block)
    end
  end

  describe "the login page" do
    it "posts to the real OmniAuth entry point when stub login is off" do
      get "/admin/login"

      expect(response.body).to include(%(action="/admin/auth/oidc"))
      expect(response.body).not_to include("Stub login is enabled")
    end

    it "posts to the stub route and warns when stub login is on" do
      enable_stub_login!

      get "/admin/login"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Stub login is enabled")
      expect(response.body).to include(%(action="/admin/login/stub"))
      expect(response.body).not_to include(%(action="/admin/auth/oidc"))
      expect(response.body).to include(ActiveAdmin::Oidc.config.login_button_label)
    end

    # Regression: the banner used to carry Tailwind colour utilities that
    # no host ever compiled, because the gem's views sit outside the
    # host's Tailwind content path -- it rendered white on white in dark
    # mode. AA 4 reuses the classes AA's own error flash emits; AA 3 has
    # no Tailwind and no dark mode, so it styles itself inline.
    it "styles the warning with something the host's build actually has" do
      enable_stub_login!

      get "/admin/login"

      if ActiveAdmin::Oidc.aa_v4?
        expect(response.body).to match(
          /class="activeadmin-oidc-stub-login[^"]*\bdark:bg-red-800\b/
        )
      else
        expect(response.body).to match(
          /class="activeadmin-oidc-stub-login"[^>]*style="[^"]*background:/
        )
      end
    end
  end

  describe "POST /admin/login/stub" do
    it "is not routable when stub login is disabled" do
      expect { post "/admin/login/stub" }
        .to raise_error(ActionController::RoutingError)
    end

    it "provisions the admin user from the default claims and signs in" do
      enable_stub_login!

      expect { post "/admin/login/stub" }.to change(AdminUser, :count).by(1)

      user = AdminUser.find_by(email: "stub-dev@example.com")
      expect(user).not_to be_nil
      # provider is the gem's own, never a separate "stub"/"test" value:
      # a row stamped with a different provider could never be matched by
      # a later real SSO login, and would trip the takeover guard.
      expect(user.provider).to eq("oidc")
      expect(user.uid).to eq("stub-uid")
      expect(user.oidc_raw_info).to include("sub" => "stub-uid")

      expect(response).to be_redirect
      expect(URI(response.location).path).to eq("/admin")
    end

    it "signs in with the claims the block returns" do
      ActiveAdmin::Oidc.config.on_login = lambda { |admin_user, claims|
        admin_user.department = claims["department"]
        true
      }
      enable_stub_login! { |claims| claims.merge("email" => "dev@example.com", "department" => "ops") }

      post "/admin/login/stub"

      user = AdminUser.find_by(email: "dev@example.com")
      expect(user).not_to be_nil
      expect(user.department).to eq("ops")
    end

    it "accepts a block that mutates the claims instead of returning them" do
      enable_stub_login! { |claims| claims["email"] = "mutated@example.com" }

      expect { post "/admin/login/stub" }.to change(AdminUser, :count).by(1)
      expect(AdminUser.find_by(email: "mutated@example.com")).not_to be_nil
    end

    it "stringifies nested keys the block returns" do
      enable_stub_login! { |claims| claims.merge(roles: { admin: true }) }
      seen = nil
      ActiveAdmin::Oidc.config.on_login = lambda { |_admin_user, claims|
        seen = claims
        true
      }

      post "/admin/login/stub"

      expect(seen.dig("roles", "admin")).to be(true)
    end

    it "never lets the block mutate the default claims" do
      enable_stub_login! { |claims| claims["email"] = "first@example.com"; claims }

      post "/admin/login/stub"

      expect(ActiveAdmin::Oidc::Configuration::DEFAULT_STUB_DEV_ENV_LOGIN_CLAIMS)
        .to eq("sub" => "stub-uid", "email" => "stub-dev@example.com")
    end

    it "reuses the existing row on a second stub login" do
      enable_stub_login!

      post "/admin/login/stub"
      expect { post "/admin/login/stub" }.not_to change(AdminUser, :count)
    end

    it "re-evaluates the block on every sign-in" do
      identity = "first@example.com"
      enable_stub_login! { |claims| claims.merge("email" => identity) }

      post "/admin/login/stub"
      expect(AdminUser.find_by(email: "first@example.com")).not_to be_nil

      identity = "second@example.com"
      post "/admin/login/stub"
      expect(AdminUser.find_by(email: "second@example.com")).not_to be_nil
    end

    it "runs the host's on_login hook and honours a denial" do
      called_with = nil
      ActiveAdmin::Oidc.config.on_login = lambda { |_admin_user, claims|
        called_with = claims
        false
      }
      enable_stub_login!

      expect { post "/admin/login/stub" }.not_to change(AdminUser, :count)

      expect(called_with).to include("sub" => "stub-uid", "email" => "stub-dev@example.com")
      expect(response).to redirect_to("/admin/login")
      follow_redirect!
      expect(response.body).to include(ActiveAdmin::Oidc.config.access_denied_message)
    end

    it "honours active_for_authentication? just like a real callback" do
      ActiveAdmin::Oidc.config.on_login = lambda { |admin_user, _claims|
        admin_user.enabled = false
        true
      }
      enable_stub_login!

      expect { post "/admin/login/stub" }.not_to change(AdminUser, :count)
      expect(response).to redirect_to("/admin/login")
    end

    it "denies claims the provisioner cannot use, like the real IdP would" do
      enable_stub_login! { |_claims| { "sub" => "stub-uid" } } # no identity claim

      expect { post "/admin/login/stub" }.not_to change(AdminUser, :count)

      follow_redirect!
      expect(response.body).to include(ActiveAdmin::Oidc.config.access_denied_message)
    end

    it "404s when the flag is flipped off after the route was drawn" do
      enable_stub_login!
      allow(ActiveAdmin::Oidc.config)
        .to receive(:stub_dev_env_login_enabled?).and_return(false)

      post "/admin/login/stub"

      expect(response).to have_http_status(:not_found)
    end
  end
end
