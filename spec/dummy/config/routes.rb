# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)
  # Intentionally no `root` route. The gem's OmniauthCallbacksController
  # must redirect into the ActiveAdmin namespace directly — not rely on
  # the host app to supply a `/` route. If the redirect regresses to
  # Devise's default, these request specs will break with a missing
  # route error, which is exactly what we want.
end
