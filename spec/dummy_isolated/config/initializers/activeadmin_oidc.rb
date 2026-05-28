# frozen_string_literal: true

ActiveAdmin::Oidc.configure do |c|
  c.issuer    = "https://idp.example.com"
  c.client_id = "client-abc"
  c.on_login  = ->(_admin_user, _claims) { true }

  # Isolated engine mounted at /admin: paths inside the engine route
  # set are prefixed by the mount path, so the default `/admin/login`
  # would become `/admin/admin/login`. Use relative paths instead.
  c.login_path  = "/login"
  c.logout_path = "/logout"
end
