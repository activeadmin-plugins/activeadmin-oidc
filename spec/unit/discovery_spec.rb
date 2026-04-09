# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveAdmin::Oidc::Discovery do
  let(:issuer) { "https://idp.example.com" }
  let(:config) do
    ActiveAdmin::Oidc::Configuration.new.tap do |c|
      c.issuer    = issuer
      c.client_id = "client-abc"
      c.on_login  = ->(_a, _c) { true }
    end
  end

  subject(:discovery) { described_class.new(config) }

  describe "#document (happy path)" do
    before { OidcStubs.stub_discovery(issuer: issuer) }

    it "fetches the .well-known/openid-configuration document" do
      discovery.document
      expect(WebMock).to have_requested(:get, "#{issuer}/.well-known/openid-configuration")
    end

    it "exposes authorization_endpoint" do
      expect(discovery.authorization_endpoint).to eq("#{issuer}/oauth/authorize")
    end

    it "exposes token_endpoint" do
      expect(discovery.token_endpoint).to eq("#{issuer}/oauth/token")
    end

    it "exposes userinfo_endpoint" do
      expect(discovery.userinfo_endpoint).to eq("#{issuer}/oauth/userinfo")
    end

    it "exposes jwks_uri" do
      expect(discovery.jwks_uri).to eq("#{issuer}/oauth/keys")
    end

    it "exposes end_session_endpoint" do
      expect(discovery.end_session_endpoint).to eq("#{issuer}/oauth/end_session")
    end

    it "exposes issuer" do
      expect(discovery.issuer).to eq(issuer)
    end

    it "memoizes the document across calls" do
      discovery.authorization_endpoint
      discovery.token_endpoint
      discovery.jwks_uri
      expect(WebMock).to have_requested(:get, "#{issuer}/.well-known/openid-configuration").once
    end
  end

  describe "overrides" do
    before { OidcStubs.stub_discovery(issuer: issuer) }

    it "allows overriding authorization_endpoint via config" do
      config.define_singleton_method(:authorization_endpoint_override) { "https://override.example/auth" }
      allow(config).to receive(:authorization_endpoint_override).and_return("https://override.example/auth")
      expect(discovery.authorization_endpoint(override: "https://override.example/auth"))
        .to eq("https://override.example/auth")
    end
  end

  describe "error modes" do
    it "raises DiscoveryError on non-2xx response" do
      OidcStubs.stub_discovery(issuer: issuer, status: 500, body: "boom")
      expect { discovery.document }.to raise_error(ActiveAdmin::Oidc::DiscoveryError, /500/)
    end

    it "raises DiscoveryError on malformed JSON" do
      OidcStubs.stub_discovery(issuer: issuer, body: "not-json")
      expect { discovery.document }.to raise_error(ActiveAdmin::Oidc::DiscoveryError, /json/i)
    end

    it "raises DiscoveryError on timeout" do
      OidcStubs.stub_discovery_timeout(issuer: issuer)
      expect { discovery.document }.to raise_error(ActiveAdmin::Oidc::DiscoveryError, /timeout|timed out/i)
    end

    it "raises DiscoveryError when issuer in document does not match configured issuer" do
      OidcStubs.stub_discovery(issuer: issuer, issuer_override: "https://evil.example.com")
      expect { discovery.document }.to raise_error(ActiveAdmin::Oidc::DiscoveryError, /issuer mismatch/i)
    end
  end
end
