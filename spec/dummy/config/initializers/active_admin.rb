# frozen_string_literal: true

ActiveAdmin.setup do |config|
  config.site_title = "Dummy"
  config.authentication_method = :authenticate_admin_user!
  config.current_user_method   = :current_admin_user
  config.logout_link_path = :destroy_admin_user_session_path

  config.root_to = "dashboard#index"
  config.comments = false

  config.default_namespace = :admin

  config.namespace :admin do |admin|
    admin.build_menu :default do |menu|
      menu.add label: "Dashboard", priority: 1, url: "/admin"
    end
  end
end
