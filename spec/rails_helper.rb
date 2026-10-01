# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require "spec_helper"
require_relative "dummy/config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "webmock/rspec"

# Load the dummy schema into the in-memory sqlite DB.
ActiveRecord::Schema.verbose = false
load File.expand_path("dummy/db/schema.rb", __dir__)

# Draw the routes once, up front, and leave them marked as loaded.
#
# Rails 8 loads routes lazily in test, so without this the draw happens
# whenever the first example touches the route set -- and it inherits
# whatever stubs that example has installed. An example that stubs
# `ActiveAdmin.application.default_namespace` and then reads
# `Devise.mappings` (which calls `reload_routes_unless_loaded` internally)
# would draw the whole app under the stubbed namespace and leak that route
# set into every later example. That is what made the suite depend on the
# random seed.
#
# `reload_routes!` is deliberately NOT used here: on a not-yet-loaded app
# it draws the routes and then resets the loaded flag back to false, so
# the next `Devise.mappings` call would redraw them anyway. `try` keeps
# this working on Rails 7.2, which has no lazy route loading and no such
# method -- the same call Devise itself makes.
Rails.application.try(:reload_routes_unless_loaded)

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end

OmniAuth.config.test_mode = true
OmniAuth.config.logger = Logger.new(File::NULL)
# Skip OmniAuth 2.x's POST CSRF validation in request specs so we can drive
# the callback flow without generating a real authenticity token.
OmniAuth.config.request_validation_phase = ->(_env) { }
# Let the request phase short-circuit via test mode mock_auth without
# trying to hit an actual IdP for discovery.
OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning    = true if OmniAuth.config.respond_to?(:silence_get_warning=)
