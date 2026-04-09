# frozen_string_literal: true

require "activeadmin/oidc/version"

module ActiveAdmin
  module Oidc
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class DiscoveryError < Error; end
    class ProvisioningError < Error; end

    class << self
      def config
        @config ||= Configuration.new
      end

      def configure
        yield config
        config
      end

      def reset!
        @config = Configuration.new
      end
    end
  end
end

require "activeadmin/oidc/configuration"
require "activeadmin/oidc/discovery"
require "activeadmin/oidc/presets/zitadel"
require "activeadmin/oidc/user_provisioner"
