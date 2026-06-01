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
end

Bundler.require(*Rails.groups)

require "devise"
require "activeadmin"
require "activeadmin-oidc"

# Exercise the engine-mounted-Devise integration with an isolated
# in-tree engine. devise_for + ActiveAdmin live inside the engine,
# Devise's URL helpers are pinned to it via `router_name: :admin_panel`.
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "admin_panel"

module Dummy
  class Application < Rails::Application
    rails_gem_version = Gem::Version.new(Rails.version)
    config.load_defaults(rails_gem_version >= Gem::Version.new("8.0") ? 8.0 : 7.2)
    config.eager_load = false
    config.root = File.expand_path("..", __dir__)

    config.secret_key_base = "test-secret-key-base-#{"x" * 64}"
    config.hosts.clear

    config.action_controller.allow_forgery_protection = false
    config.session_store :cookie_store, key: "_dummy_engine_session"

    config.action_dispatch.show_exceptions = :none
    config.consider_all_requests_local = true
    config.active_support.to_time_preserves_timezone = :zone if config.active_support.respond_to?(:to_time_preserves_timezone=)

    config.logger = Logger.new($stdout)
    config.log_level = ENV.fetch("DUMMY_LOG_LEVEL", "fatal").to_sym
  end
end
