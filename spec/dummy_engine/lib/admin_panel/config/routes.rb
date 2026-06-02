# frozen_string_literal: true

# Engine-mounted-Devise layout: devise_for + ActiveAdmin routes live
# inside the engine. The engine is pinned via the GLOBAL
# `Devise.router_name = :admin_panel` set in config/initializers/devise.rb
# rather than a per-mapping `router_name:` option here — this is the
# pattern hosts use most often (and the pattern under which the bug in
# OmniauthCallbacksController#after_omniauth_failure_path_for surfaces).
AdminPanel::Engine.routes.draw do
  devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)
end
