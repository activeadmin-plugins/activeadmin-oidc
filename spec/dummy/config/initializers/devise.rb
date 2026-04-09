# frozen_string_literal: true

Devise.setup do |config|
  config.mailer_sender = "please-change-me@example.com"
  require "devise/orm/active_record"

  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.skip_session_storage = [:http_auth]
  config.stretches = Rails.env.test? ? 1 : 11
  config.reconfirmable = true
  config.expire_all_remember_me_on_sign_out = true
  config.password_length = 6..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  config.reset_password_within = 6.hours
  config.sign_out_via = :delete

  # Wire omniauth_openid_connect via the gem. Deliberately lazy so that
  # specs that `reset!` the config mid-test work without warnings — we
  # register a minimal fake provider up front and rely on the test suite
  # to mock omniauth.auth.
  require "omniauth_openid_connect"

  config.omniauth :openid_connect,
                  name:          :oidc,
                  issuer:        "https://idp.example.com",
                  discovery:     false,
                  scope:         %i[openid email profile],
                  response_type: :code,
                  client_options: {
                    identifier: "client-abc",
                    secret:     "client-secret",
                    port:       443,
                    scheme:     "https",
                    host:       "idp.example.com",
                    authorization_endpoint: "/oauth/authorize",
                    token_endpoint:         "/oauth/token",
                    userinfo_endpoint:      "/oauth/userinfo",
                    jwks_uri:               "/oauth/keys"
                  }
end
