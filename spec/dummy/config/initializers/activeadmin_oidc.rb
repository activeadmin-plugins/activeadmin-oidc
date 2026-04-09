# frozen_string_literal: true

ActiveAdmin::Oidc.configure do |c|
  c.issuer    = "https://idp.example.com"
  c.client_id = "client-abc"
  # client_secret intentionally blank so PKCE auto-enables in specs.
  c.on_login = ->(admin_user, claims) {
    # Default dummy on_login: accept, set department if provided.
    admin_user.department = claims["department"] if claims.key?("department")
    true
  }
end
