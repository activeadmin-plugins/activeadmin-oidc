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

  describe "paths derived from ActiveAdmin's namespace" do
    # `default_namespace` is one of ActiveAdmin's dynamically defined
    # settings, so a verifying double refuses it.
    def with_namespace(namespace)
      without_partial_double_verification do
        allow(ActiveAdmin).to receive(:application)
          .and_return(double("ActiveAdmin::Application", default_namespace: namespace))
        yield
      end
    end

    it "follows a renamed default_namespace" do
      with_namespace(:backoffice) do
        expect(config.login_path).to eq("/backoffice/login")
        expect(config.logout_path).to eq("/backoffice/logout")
        expect(config.omniauth_path_prefix).to eq("/backoffice/auth")
      end
    end

    it "mounts at the top level for ActiveAdmin's root namespace" do
      with_namespace(:root) do
        expect(config.login_path).to eq("/login")
        expect(config.omniauth_path_prefix).to eq("/auth")
      end
    end

    it "treats a blank namespace as the root namespace" do
      with_namespace(false) { expect(config.login_path).to eq("/login") }
    end

    it "keeps an explicit override, which isolated engines depend on" do
      config.login_path  = "/login"
      config.logout_path = "/logout"

      with_namespace(:backoffice) do
        expect(config.login_path).to eq("/login")
        expect(config.logout_path).to eq("/logout")
        # ...without dragging the derived prefix along with it.
        expect(config.omniauth_path_prefix).to eq("/backoffice/auth")
      end
    end

    it "defaults omniauth_route_prefix to omniauth_path_prefix" do
      with_namespace(:backoffice) do
        expect(config.omniauth_route_prefix).to eq("/backoffice/auth")
      end
    end

    # Engine-mounted hosts split the two: the middleware sees the
    # browser-visible path, Devise declares its routes engine-relative.
    it "lets omniauth_route_prefix be overridden independently" do
      config.omniauth_route_prefix = "/auth"

      with_namespace(:admin) do
        expect(config.omniauth_path_prefix).to eq("/admin/auth")
        expect(config.omniauth_route_prefix).to eq("/auth")
      end
    end

    # Library code has to stay callable with no ActiveAdmin around at
    # all (unit specs, scripts). Driven by raising rather than by the
    # absence of the constant, so it holds whether or not another spec
    # in the same process has booted the dummy app.
    it "falls back to /admin when ActiveAdmin cannot be consulted" do
      without_partial_double_verification do
        allow(ActiveAdmin).to receive(:application).and_raise(NoMethodError)
      end

      expect(config.login_path).to eq("/admin/login")
      expect(config.logout_path).to eq("/admin/logout")
      expect(config.omniauth_path_prefix).to eq("/admin/auth")
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
