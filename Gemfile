# frozen_string_literal: true

source "https://rubygems.org"

gemspec

default_rails_version       = "7.2.0"
default_activeadmin_version = "3.5.0"

rails_version       = ENV.fetch("RAILS", default_rails_version)
activeadmin_version = ENV.fetch("AA",    default_activeadmin_version)
# 0.6.x uses openid_connect 1.x (httpclient, no faraday) — required for
# host apps still on faraday 1.x. 0.7.x uses openid_connect 2.x (faraday 2.x).
ooidc_version       = ENV["OOIDC"]

gem "rails",        "~> #{rails_version}"
gem "activerecord", "~> #{rails_version}"
gem "activeadmin",  "~> #{activeadmin_version}"
gem "omniauth_openid_connect", "~> #{ooidc_version}" if ooidc_version
