# frozen_string_literal: true

module ActiveAdmin
  module Oidc
    # Builds the options hash the host app passes to
    # `Devise.setup { |c| c.omniauth :openid_connect, ... }`. Shape is
    # determined by the upstream `omniauth_openid_connect` gem.
    module OmniauthOptions
      module_function

      def build(config = ActiveAdmin::Oidc.config)
        config.validate!

        {
          name:          Engine::PROVIDER_NAME,
          issuer:        config.issuer,
          discovery:     true,
          scope:         config.scope.to_s.split(/\s+/).map(&:to_sym),
          response_type: :code,
          pkce:          config.pkce,
          client_options: {
            identifier:   config.issuer && config.client_id,
            secret:       config.client_secret,
            port:         nil,
            scheme:       nil,
            host:         nil
          }.compact
        }
      end
    end
  end
end
