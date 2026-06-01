# frozen_string_literal: true

Rails.application.routes.draw do
  # Non-isolated AdminPanel::Engine. The engine's own config/routes.rb
  # is drawn into AdminPanel::Engine.routes via the Rails::Engine
  # railtie; mounting it here makes those routes reachable from the
  # main app's dispatcher (so Capybara visits resolve). Guard against
  # double-mount when Rails re-evaluates the route set during boot.
  unless Rails.application.routes.named_routes.key?(:admin_panel)
    mount AdminPanel::Engine => "/"
  end
end
