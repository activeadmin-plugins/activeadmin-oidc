# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveAdmin::Oidc::Configuration do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "has a default scope of openid email profile" do
      expect(config.scope).to eq("openid email profile")
    end

    it "has a default timeout of 5 seconds" do
      expect(config.timeout).to eq(5)
    end

    it "has a default identity_attribute of :email" do
      expect(config.identity_attribute).to eq(:email)
    end

    it "has a default identity_claim of :email" do
      expect(config.identity_claim).to eq(:email)
    end

    it "has a default login_button_label" do
      expect(config.login_button_label).to be_a(String)
      expect(config.login_button_label).not_to be_empty
    end

    it "has a generic access_denied_message default" do
      expect(config.access_denied_message).to be_a(String)
      expect(config.access_denied_message).to match(/permission/i)
    end

    it "defaults admin_user_class to the string 'AdminUser'" do
      expect(config.admin_user_class).to eq("AdminUser")
    end

    it "has no issuer by default" do
      expect(config.issuer).to be_nil
    end

    it "has no client_id by default" do
      expect(config.client_id).to be_nil
    end

    it "has no client_secret by default" do
      expect(config.client_secret).to be_nil
    end

    it "has no on_login by default" do
      expect(config.on_login).to be_nil
    end
  end

  describe ".configure" do
    after { ActiveAdmin::Oidc.reset! }

    it "yields the singleton configuration" do
      yielded = nil
      ActiveAdmin::Oidc.configure { |c| yielded = c }
      expect(yielded).to be(ActiveAdmin::Oidc.config)
    end

    it "memoizes the singleton across calls" do
      first  = ActiveAdmin::Oidc.config
      second = ActiveAdmin::Oidc.config
      expect(first).to be(second)
    end

    it "persists values set inside the block" do
      ActiveAdmin::Oidc.configure do |c|
        c.issuer    = "https://example.com"
        c.client_id = "abc"
      end
      expect(ActiveAdmin::Oidc.config.issuer).to eq("https://example.com")
      expect(ActiveAdmin::Oidc.config.client_id).to eq("abc")
    end
  end

  describe "#validate!" do
    before do
      config.issuer    = "https://example.com"
      config.client_id = "abc"
      config.on_login  = ->(admin_user, claims) { true }
    end

    it "does not raise when issuer, client_id and on_login are set" do
      expect { config.validate! }.not_to raise_error
    end

    it "does not require client_secret (PKCE public client)" do
      config.client_secret = nil
      expect { config.validate! }.not_to raise_error
    end

    it "raises ConfigurationError when issuer is blank" do
      config.issuer = nil
      expect { config.validate! }.to raise_error(ActiveAdmin::Oidc::ConfigurationError, /issuer/)
    end

    it "raises ConfigurationError when client_id is blank" do
      config.client_id = ""
      expect { config.validate! }.to raise_error(ActiveAdmin::Oidc::ConfigurationError, /client_id/)
    end

    it "raises ConfigurationError when on_login is nil" do
      config.on_login = nil
      expect { config.validate! }.to raise_error(ActiveAdmin::Oidc::ConfigurationError, /on_login/)
    end

    it "raises ConfigurationError when on_login is not callable" do
      config.on_login = "not a proc"
      expect { config.validate! }.to raise_error(ActiveAdmin::Oidc::ConfigurationError, /on_login/)
    end

  end

  describe "stub login configuration" do
    it "is disabled by default" do
      expect(config.stub_dev_env_login_enabled?).to be(false)
    end

    it "refuses to enable outside the development environment" do
      expect(config.stub_dev_env_login!).to be(false)
      expect(config.stub_dev_env_login_enabled?).to be(false)
    end

    context "in the development environment" do
      before do
        allow(Rails).to receive(:env).and_return(
          ActiveSupport::StringInquirer.new("development")
        )
      end

      it "enables without a block" do
        expect(config.stub_dev_env_login!).to be(true)
        expect(config.stub_dev_env_login_enabled?).to be(true)
        expect(config.stub_dev_env_login_claims_block).to be_nil
      end

      it "defaults to claims that satisfy the default identity_claim" do
        config.stub_dev_env_login!

        expect(config.stub_dev_env_login_claims)
          .to eq("sub" => "stub-uid", "email" => "stub-dev@example.com")
      end

      it "passes the default claims to the block and uses what it returns" do
        config.stub_dev_env_login! { |claims| claims.merge("groups" => ["admins"]) }

        expect(config.stub_dev_env_login_claims).to eq(
          "sub" => "stub-uid", "email" => "stub-dev@example.com", "groups" => ["admins"]
        )
      end

      it "accepts a block that mutates the claims instead of returning them" do
        # `claims["groups"] = [...]` as a last line returns the assigned
        # value, not the Hash.
        config.stub_dev_env_login! { |claims| claims["groups"] = ["admins"] }

        expect(config.stub_dev_env_login_claims).to eq(
          "sub" => "stub-uid", "email" => "stub-dev@example.com", "groups" => ["admins"]
        )
      end

      it "stringifies nested symbol keys so the claims match what on_login receives" do
        config.stub_dev_env_login! { |claims| claims.merge(roles: { admin: true }) }

        expect(config.stub_dev_env_login_claims["roles"]).to eq("admin" => true)
      end

      it "never lets the block mutate the defaults" do
        config.stub_dev_env_login! { |claims| claims["email"] = "dev@example.com"; claims }
        config.stub_dev_env_login_claims

        expect(described_class::DEFAULT_STUB_DEV_ENV_LOGIN_CLAIMS)
          .to eq("sub" => "stub-uid", "email" => "stub-dev@example.com")
      end

      it "calls the block on every read, so the identity can come from ENV" do
        calls = 0
        config.stub_dev_env_login! do |claims|
          calls += 1
          claims.merge("email" => "dev#{calls}@example.com")
        end

        expect(config.stub_dev_env_login_claims["email"]).to eq("dev1@example.com")
        expect(config.stub_dev_env_login_claims["email"]).to eq("dev2@example.com")
      end

      it "is cleared by reset!" do
        config.stub_dev_env_login!
        config.reset!

        expect(config.stub_dev_env_login_enabled?).to be(false)
        expect(config.stub_dev_env_login_claims_block).to be_nil
      end
    end
  end

  describe "#login_submit_path" do
    it "points at the OmniAuth entry point when stub login is off" do
      expect(config.login_submit_path)
        .to eq("#{OmniAuth.config.path_prefix}/oidc")
    end

    it "points at the stub route, derived from login_path, when stub login is on" do
      allow(config).to receive(:stub_dev_env_login_enabled?).and_return(true)
      config.login_path = "/admin/login"

      expect(config.login_submit_path).to eq("/admin/login/stub")
    end
  end

  describe "#pkce" do
    it "defaults to true when client_secret is blank" do
      config.client_secret = nil
      expect(config.pkce).to be(true)
    end

    it "defaults to false when client_secret is present" do
      config.client_secret = "secret"
      expect(config.pkce).to be(false)
    end

    it "respects explicit pkce = true even when a secret is set" do
      config.client_secret = "secret"
      config.pkce = true
      expect(config.pkce).to be(true)
    end

    it "respects explicit pkce = false even when no secret is set" do
      config.client_secret = nil
      config.pkce = false
      expect(config.pkce).to be(false)
    end
  end

  describe "accessors" do
    it "round-trips all documented accessors" do
      config.issuer              = "https://example.com"
      config.client_id           = "id"
      config.client_secret       = "sec"
      config.scope               = "openid email"
      config.login_button_label  = "Sign in"
      config.timeout             = 10
      config.identity_attribute  = :username
      config.identity_claim      = :preferred_username
      config.access_denied_message = "nope"
      config.on_login            = ->(_a, _c) { true }
      config.pkce                = true

      expect(config.issuer).to               eq("https://example.com")
      expect(config.client_id).to            eq("id")
      expect(config.client_secret).to        eq("sec")
      expect(config.scope).to                eq("openid email")
      expect(config.login_button_label).to   eq("Sign in")
      expect(config.timeout).to              eq(10)
      expect(config.identity_attribute).to   eq(:username)
      expect(config.identity_claim).to       eq(:preferred_username)
      expect(config.access_denied_message).to eq("nope")
      expect(config.on_login).to             be_a(Proc)
      expect(config.pkce).to                 be(true)
    end

    it "does not expose a callback_path= accessor (path is hardcoded on the engine)" do
      expect(config).not_to respond_to(:callback_path=)
    end
  end

  describe "#reset!" do
    it "restores defaults" do
      config.issuer    = "https://example.com"
      config.client_id = "abc"
      config.reset!
      expect(config.issuer).to be_nil
      expect(config.client_id).to be_nil
      expect(config.scope).to eq("openid email profile")
    end
  end
end
