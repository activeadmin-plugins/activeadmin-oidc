# frozen_string_literal: true

ActiveAdmin.setup do |config|
  config.site_title = "Dummy Engine"
  config.authentication_method = :authenticate_admin_user!
  config.current_user_method   = :current_admin_user
  config.logout_link_path = :destroy_admin_user_session_path

  config.root_to = "dashboard#index"
  config.comments = false

  config.default_namespace = :admin
end
