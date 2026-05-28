# frozen_string_literal: true

Rails.application.routes.draw do
  # Routes are re-drawn during boot for isolated engines; guard the
  # mount so the named helper isn't re-registered on the second pass.
  unless Rails.application.routes.named_routes.key?(:admin_panel)
    mount AdminPanel::Engine => "/admin"
  end
end
