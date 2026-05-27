# frozen_string_literal: true

ActiveAdmin::Oidc.configure do |c|
  c.issuer    = "https://idp.example.com"
  c.client_id = "client-abc"
  c.on_login  = ->(_admin_user, _claims) { true }
end
