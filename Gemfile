# frozen_string_literal: true

source "https://rubygems.org"

gemspec

default_rails_version       = "7.2.0"
default_activeadmin_version = "3.5.0"

rails_version       = ENV.fetch("RAILS", default_rails_version)
activeadmin_version = ENV.fetch("AA",    default_activeadmin_version)

gem "rails",        "~> #{rails_version}"
gem "activerecord", "~> #{rails_version}"
gem "activeadmin",  "~> #{activeadmin_version}"
