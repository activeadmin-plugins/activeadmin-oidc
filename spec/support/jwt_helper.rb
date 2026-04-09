# frozen_string_literal: true

require "jwt"
require "openssl"
require "base64"

module JwtHelper
  RSA_KEY = OpenSSL::PKey::RSA.generate(2048).freeze
  KID     = "test-key-1"

  module_function

  def rsa_key
    RSA_KEY
  end

  def kid
    KID
  end

  # Build a signed id_token with the given claims, defaulting to sensible
  # values. Pass `now:` to freeze time. Pass `alg:` to force a weird alg.
  def build_id_token(claims = {}, now: Time.now, alg: "RS256")
    payload = {
      iss:       "https://idp.example.com",
      sub:       "sub-123",
      aud:       "client-abc",
      exp:       (now + 600).to_i,
      iat:       now.to_i,
      nonce:     "test-nonce",
      email:     "alice@example.com"
    }.merge(claims)

    JWT.encode(payload, RSA_KEY, alg, kid: KID)
  end

  # JWK representation of the public key, in the shape the IdP would return
  # from its jwks_uri.
  def jwks
    pub = RSA_KEY.public_key
    n = Base64.urlsafe_encode64(pub.n.to_s(2), padding: false)
    e = Base64.urlsafe_encode64(pub.e.to_s(2), padding: false)
    {
      "keys" => [
        {
          "kty" => "RSA",
          "kid" => KID,
          "use" => "sig",
          "alg" => "RS256",
          "n"   => n,
          "e"   => e
        }
      ]
    }
  end
end
