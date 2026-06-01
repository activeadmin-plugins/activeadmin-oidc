# frozen_string_literal: true

require 'omniauth'

module ActiveAdmin
  module Oidc
    # Test helpers for host apps. Include in your RSpec config:
    #
    #   require "activeadmin/oidc/test_helpers"
    #
    #   RSpec.configure do |config|
    #     config.include ActiveAdmin::Oidc::TestHelpers, oidc_mode: true
    #     config.after(:each, :oidc_mode) { reset_oidc_stubs }
    #   end
    #
    # Then in specs tagged `oidc_mode: true`:
    #
    #   before { stub_oidc_sign_in(sub: "alice-sub", claims: { "email" => "a@b" }) }
    #
    module TestHelpers
      DEFAULT_CLAIMS = {
        'preferred_username' => 'alice',
        'email' => 'alice@test',
        'roles' => ['admin']
      }.freeze

      # Stubs OmniAuth to return a successful OIDC auth hash.
      # Merges the given claims with DEFAULT_CLAIMS.
      def stub_oidc_sign_in(sub: 'alice-sub', claims: {})
        merged = DEFAULT_CLAIMS.merge(claims.transform_keys(&:to_s))
        OmniAuth.config.test_mode = true
        # OmniAuth 2.x still runs request_validation_phase in test mode
        # (mock_request_call, line 325 of strategy.rb). Disable it so
        # the CSRF check from omniauth-rails_csrf_protection doesn't
        # reject the mocked request.
        @_oidc_saved_request_validation_phase = OmniAuth.config.request_validation_phase
        OmniAuth.config.request_validation_phase = nil
        OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new(
          provider: 'oidc',
          uid: sub,
          info: {
            email: merged['email'],
            name: merged['name'],
            nickname: merged['preferred_username']
          },
          credentials: {},
          extra: { raw_info: merged.merge('sub' => sub) }
        )
      end

      # Stubs OmniAuth to simulate a strategy failure.
      def stub_oidc_failure(message_key = :invalid_credentials)
        OmniAuth.config.test_mode = true
        @_oidc_saved_request_validation_phase = OmniAuth.config.request_validation_phase
        OmniAuth.config.request_validation_phase = nil
        OmniAuth.config.mock_auth[:oidc] = message_key
      end

      # Resets OmniAuth test mode. Call in an `after` hook.
      def reset_oidc_stubs
        OmniAuth.config.mock_auth[:oidc] = nil
        OmniAuth.config.test_mode = false
        OmniAuth.config.request_validation_phase = @_oidc_saved_request_validation_phase if defined?(@_oidc_saved_request_validation_phase)
      end
    end
  end
end
