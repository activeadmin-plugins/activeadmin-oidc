# frozen_string_literal: true

require "logger"
require "active_support/core_ext/object/blank"
require "activeadmin/oidc/version"

# `omniauth-rails_csrf_protection` registers a Railtie that replaces
# OmniAuth 2.x's Rack-level authenticity check with Rails' own forgery
# protection. It's a runtime dependency of this gem, but `Bundler.require`
# in host apps only auto-requires top-level Gemfile entries — not
# transitive deps pulled in via our gemspec. We `require` it here so
# that the railtie gets loaded whenever a host does
# `gem "activeadmin-oidc"`, and CSRF-protected OmniAuth POSTs work
# out of the box with `button_to`-style login buttons.
#
# `omniauth/rails_csrf_protection/railtie` references `Rails::Railtie`
# at file load, so pull in the minimal Railtie base class first — this
# keeps the require safe even in spec_helper contexts where the full
# Rails stack hasn't been initialized yet.
require "rails/railtie"
require "omniauth/rails_csrf_protection"

module ActiveAdmin
  module Oidc
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class ProvisioningError < Error; end

    class << self
      def config
        @config ||= Configuration.new
      end

      def configure
        yield config
        config
      end

      # Logger the gem uses for internal diagnostics (on_login hook
      # failures, omniauth failures, etc). Defaults to Rails.logger when
      # Rails is booted, falls back to a null logger otherwise so that
      # library code is safe to call in non-Rails contexts (unit specs,
      # scripts). Override by assigning directly — useful in tests.
      def logger
        @logger || default_logger
      end

      attr_writer :logger

      def reset!
        @config = Configuration.new
        @logger = nil
      end

      private

      def default_logger
        if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
          ::Rails.logger
        else
          @null_logger ||= ::Logger.new(IO::NULL)
        end
      end
    end
  end
end

require "activeadmin/oidc/configuration"
require "activeadmin/oidc/user_provisioner"
require "rails/engine"
require "activeadmin/oidc/engine"
