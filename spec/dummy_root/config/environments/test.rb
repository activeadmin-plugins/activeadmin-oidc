# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = false
  config.public_file_server.enabled = true
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false
  config.action_dispatch.show_exceptions = :none
  config.action_controller.allow_forgery_protection = false
  config.active_support.deprecation = :stderr
  config.active_support.disallowed_deprecation = :raise
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: "www.example.com" }
  config.i18n.raise_on_missing_translations = false
  config.log_level = :fatal
end
