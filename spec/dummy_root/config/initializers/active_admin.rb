# frozen_string_literal: true

ActiveAdmin.setup do |config|
  config.site_title = "Dummy Root"
  config.authentication_method = :authenticate_admin_user!
  config.current_user_method   = :current_admin_user
  config.logout_link_path = :destroy_admin_user_session_path

  config.root_to = "dashboard#index"
  config.comments = false

  # The whole point of this dummy app: ActiveAdmin mounted at `/`, not
  # `/admin`. Real hosts do this when the admin panel *is* the app.
  config.default_namespace = false
end
