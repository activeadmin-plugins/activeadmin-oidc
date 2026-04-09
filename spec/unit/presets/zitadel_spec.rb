# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveAdmin::Oidc::Presets::Zitadel do
  let(:config) { ActiveAdmin::Oidc::Configuration.new }

  describe ".apply" do
    it "sets the default scope" do
      described_class.apply(config)
      expect(config.scope).to eq("openid email profile")
    end

    it "enables pkce when client_secret is blank" do
      config.client_secret = nil
      described_class.apply(config)
      expect(config.pkce).to be(true)
    end

    it "does not touch pkce when client_secret is set" do
      config.client_secret = "secret"
      described_class.apply(config)
      expect(config.pkce).to be(false)
    end

    it "does not override user-set issuer" do
      config.issuer = "https://custom.example.com"
      described_class.apply(config)
      expect(config.issuer).to eq("https://custom.example.com")
    end

    it "does not override user-set client_id" do
      config.client_id = "custom-id"
      described_class.apply(config)
      expect(config.client_id).to eq("custom-id")
    end

    it "does not override user-set client_secret" do
      config.client_secret = "custom-secret"
      described_class.apply(config)
      expect(config.client_secret).to eq("custom-secret")
    end

    it "does not override a user-set scope" do
      config.scope = "openid profile custom:scope"
      described_class.apply(config)
      expect(config.scope).to eq("openid profile custom:scope")
    end

    it "does not override an explicit pkce = false on a public client" do
      config.client_secret = nil
      config.pkce = false
      described_class.apply(config)
      expect(config.pkce).to be(false)
    end

    it "does not override a user-set on_login" do
      hook = ->(_a, _c) { true }
      config.on_login = hook
      described_class.apply(config)
      expect(config.on_login).to be(hook)
    end

    it "is idempotent" do
      described_class.apply(config)
      first = [config.scope, config.pkce]
      described_class.apply(config)
      expect([config.scope, config.pkce]).to eq(first)
    end
  end
end
