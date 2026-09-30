# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)
  # No host-defined `root` route: ActiveAdmin's own `root_to` supplies
  # `/`. Anything the gem redirects to outside the ActiveAdmin route
  # table therefore 404s, which is what these specs are here to catch.
end
