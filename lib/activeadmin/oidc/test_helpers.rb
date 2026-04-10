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
        OmniAuth.config.mock_auth[:oidc] = message_key
      end

      # Resets OmniAuth test mode. Call in an `after` hook.
      def reset_oidc_stubs
        OmniAuth.config.mock_auth[:oidc] = nil
        OmniAuth.config.test_mode = false
      end
    end

    # RSpec support for oidc_mode tag filtering.
    # Require this file in spec_helper or rails_helper to auto-configure:
    #
    #   require "activeadmin/oidc/test_helpers"
    #
    # Specs tagged `oidc_mode: true` will be skipped unless the AdminUser
    # model has :omniauthable loaded. Set CI_RUN_OIDC=true in your CI job
    # to run only OIDC-tagged specs.
    module RSpecSupport
      def self.install!
        return unless defined?(RSpec)

        RSpec.configure do |config|
          config.include TestHelpers, oidc_mode: true
          config.after(:each, :oidc_mode) { reset_oidc_stubs }

          config.before(:each, :oidc_mode) do
            admin_class = ActiveAdmin::Oidc.config.admin_user_class
            klass = admin_class.is_a?(String) ? admin_class.safe_constantize : admin_class
            unless klass.respond_to?(:devise_modules) && klass.devise_modules.include?(:omniauthable)
              skip 'requires OIDC mode (run with config/oidc.yml in place and CI_RUN_OIDC=true)'
            end
          end

          if ENV['CI_RUN_OIDC'].present?
            config.filter_run_including oidc_mode: true
          else
            config.filter_run_excluding oidc_mode: true
          end
        end
      end
    end
  end
end

# Auto-install RSpec support when required during a test run.
ActiveAdmin::Oidc::RSpecSupport.install!
