# frozen_string_literal: true

Rails.application.routes.draw do
  # Non-isolated AdminPanel::Engine: its routes (devise_for +
  # ActiveAdmin) get drawn into AdminPanel::Engine.routes, which is
  # itself a route set discovered by Rails::Engine railtie. No
  # explicit `mount` needed — that would conflict because the engine
  # registers itself once already.
end
