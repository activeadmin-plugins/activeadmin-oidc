# frozen_string_literal: true

module ActiveAdmin
  module Oidc
    module Presets
      module Zitadel
        DEFAULT_SCOPE = "openid email profile"

        def self.apply(config)
          config.scope = DEFAULT_SCOPE if config.scope == Configuration::DEFAULT_SCOPE
          config.pkce  = true if config.client_secret.blank? && config.instance_variable_get(:@pkce_override).nil?
          config
        end
      end
    end
  end
end
