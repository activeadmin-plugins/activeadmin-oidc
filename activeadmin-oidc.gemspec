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
  spec.homepage = "https://github.com/activeadmin-plugins/activeadmin-oidc"

  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir[
    "lib/**/*",
    "app/**/*",
    "config/**/*",
    "README.md",
    "LICENSE.txt"
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "activeadmin",            ">= 3.5", "< 5"
  # Devise 5.0 wraps `Devise.mappings` with `reload_routes_unless_loaded`
  # (heartcombo/devise#5728) so OmniAuth's failure handler works under
  # Rails 8 lazy route loading without an engine-side workaround.
  spec.add_dependency "devise",                 "~> 5.0"
  spec.add_dependency "omniauth",               "~> 2.1"
  spec.add_dependency "omniauth-rails_csrf_protection", "~> 1.0"
  # 0.6.x → openid_connect 1.x (httpclient-based, no faraday dep).
  # 0.7.x+ → openid_connect 2.x (faraday 2.x). Host apps still on faraday 1.x
  # need 0.6.x. activeadmin-oidc only uses the standard OmniAuth strategy
  # registration API, which is identical across both lines.
  spec.add_dependency "omniauth_openid_connect", ">= 0.6", "< 1"
  spec.add_dependency "rails",                  ">= 7.2", "< 9"

  spec.add_development_dependency "rspec-rails",   "~> 6.0"
  spec.add_development_dependency "capybara",      "~> 3.40"
  spec.add_development_dependency "webmock",       "~> 3.19"
  spec.add_development_dependency "jwt",           "~> 2.7"
  spec.add_development_dependency "sqlite3",       ">= 1.7", "< 3"
  # The asset pipeline gems live in the per-version gemfiles under
  # gemfiles/ rather than here: ActiveAdmin 3.5 needs Sprockets + Sassc,
  # while ActiveAdmin 4.0 needs Propshaft + importmap + cssbundling +
  # Tailwind. Keeping them out of the gemspec lets each gemfile install
  # exactly one asset stack instead of both.
  spec.add_development_dependency "rake",          "~> 13.0"
  spec.add_development_dependency "rubocop",       "~> 1.60"
  spec.add_development_dependency "rubocop-rails", "~> 2.20"
  spec.add_development_dependency "rubocop-rspec", "~> 2.25"

  spec.metadata["rubygems_mfa_required"] = "true"
end
