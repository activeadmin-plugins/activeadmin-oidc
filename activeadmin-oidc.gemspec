# frozen_string_literal: true

require_relative "lib/activeadmin/oidc/version"

Gem::Specification.new do |spec|
  spec.name        = "activeadmin-oidc"
  spec.version     = ActiveAdmin::Oidc::VERSION
  spec.authors     = ["Igor Fedoronchuk"]
  spec.summary     = "OpenID Connect SSO for ActiveAdmin"
  spec.description = <<~DESC
    activeadmin-oidc plugs generic OpenID Connect single sign-on into ActiveAdmin.
    It builds on Devise + omniauth_openid_connect and adds JIT user provisioning,
    role mapping from provider claims via a host-owned on_login hook, and a
    single install generator that wires everything up.
  DESC
  spec.license  = "MIT"
  spec.homepage = "https://github.com/fedoronchuk/activeadmin-oidc"

  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir[
    "lib/**/*",
    "app/**/*",
    "config/**/*",
    "README.md",
    "LICENSE.txt"
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "activeadmin",            ">= 3.5", "< 4"
  spec.add_dependency "devise",                 ">= 4.9"
  spec.add_dependency "omniauth",               ">= 2.1"
  spec.add_dependency "omniauth-rails_csrf_protection", ">= 1.0"
  spec.add_dependency "omniauth_openid_connect", ">= 0.7"
  spec.add_dependency "rails",                  ">= 7.2"

  spec.add_development_dependency "rspec-rails",  ">= 6.0"
  spec.add_development_dependency "webmock",      ">= 3.19"
  spec.add_development_dependency "jwt",          ">= 2.7"
  spec.add_development_dependency "sqlite3",      ">= 1.7"
  spec.add_development_dependency "sprockets-rails", ">= 3.4"
  spec.add_development_dependency "sassc-rails",     ">= 2.1"
  spec.add_development_dependency "rake",         ">= 13.0"
  spec.add_development_dependency "rubocop",      ">= 1.60"
  spec.add_development_dependency "rubocop-rails", ">= 2.20"
  spec.add_development_dependency "rubocop-rspec", ">= 2.25"

  spec.metadata["rubygems_mfa_required"] = "true"
end
