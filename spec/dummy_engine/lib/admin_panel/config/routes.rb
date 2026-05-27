# frozen_string_literal: true

# Mirrors the pbx-api / yeti-web pattern: devise_for + ActiveAdmin
# routes live inside the engine, pinned to it via `router_name`.
AdminPanel::Engine.routes.draw do
  devise_for :admin_users, ActiveAdmin::Devise.config.merge(router_name: :admin_panel)
  ActiveAdmin.routes(self)
end
