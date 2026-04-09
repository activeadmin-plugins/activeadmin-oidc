# frozen_string_literal: true

require "activeadmin/oidc/version"

module ActiveAdmin
  module Oidc
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class DiscoveryError < Error; end
    class ProvisioningError < Error; end
  end
end
