# frozen_string_literal: true

require "webmock/rspec"
require "json"

module OidcStubs
  DEFAULT_ISSUER = "https://idp.example.com"

  module_function

  # Stub the discovery endpoint at <issuer>/.well-known/openid-configuration.
  # Pass overrides to tweak the returned document or `status:` to force a
  # non-200 response. The returned document claims the same `issuer` as the
  # configured one unless `issuer_override:` is set (for the mismatch spec).
  def stub_discovery(issuer: DEFAULT_ISSUER, issuer_override: nil, status: 200, body: nil)
    doc = {
      "issuer"                 => issuer_override || issuer,
      "authorization_endpoint" => "#{issuer}/oauth/authorize",
      "token_endpoint"         => "#{issuer}/oauth/token",
      "userinfo_endpoint"      => "#{issuer}/oauth/userinfo",
      "jwks_uri"               => "#{issuer}/oauth/keys",
      "end_session_endpoint"   => "#{issuer}/oauth/end_session",
      "response_types_supported" => ["code"],
      "subject_types_supported"  => ["public"],
      "id_token_signing_alg_values_supported" => ["RS256"]
    }

    WebMock.stub_request(:get, "#{issuer}/.well-known/openid-configuration")
           .to_return(
             status:  status,
             body:    body || doc.to_json,
             headers: { "Content-Type" => "application/json" }
           )
  end

  # Raise a connection timeout when discovery is fetched.
  def stub_discovery_timeout(issuer: DEFAULT_ISSUER)
    WebMock.stub_request(:get, "#{issuer}/.well-known/openid-configuration")
           .to_timeout
  end

  def stub_jwks(issuer: DEFAULT_ISSUER, body: nil)
    WebMock.stub_request(:get, "#{issuer}/oauth/keys")
           .to_return(
             status:  200,
             body:    (body || JwtHelper.jwks).to_json,
             headers: { "Content-Type" => "application/json" }
           )
  end
end
