# frozen_string_literal: true

# Isolated engine variant: devise_for + ActiveAdmin live inside the
# engine. Mount-path prefixing applies — paths declared here become
# `/admin/<path>` after `mount AdminPanel::Engine => '/admin'` in the
# main app routes.
AdminPanel::Engine.routes.draw do
  devise_for :admin_users, ActiveAdmin::Devise.config.merge(router_name: :admin_panel)
end
