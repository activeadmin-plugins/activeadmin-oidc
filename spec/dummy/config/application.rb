# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
begin
  require "sprockets/railtie"
rescue LoadError
  # sprockets-rails is optional; dummy app uses ActiveAdmin's cssbundling/importmap defaults
end

Bundler.require(*Rails.groups)

require "devise"
require "activeadmin"

# Load the gem under test.
require "activeadmin-oidc"

module Dummy
  class Application < Rails::Application
    config.load_defaults 7.2
    config.eager_load = false
    config.root = File.expand_path("..", __dir__)

    config.secret_key_base = "test-secret-key-base-#{"x" * 64}"
    config.hosts.clear

    config.action_controller.allow_forgery_protection = false
    config.session_store :cookie_store, key: "_dummy_session"
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store, config.session_options

    config.action_dispatch.show_exceptions = :none
    config.consider_all_requests_local = true
    config.active_support.to_time_preserves_timezone = :zone if config.active_support.respond_to?(:to_time_preserves_timezone=)

    config.logger = Logger.new($stdout)
    config.log_level = ENV.fetch("DUMMY_LOG_LEVEL", "fatal").to_sym
  end
end
