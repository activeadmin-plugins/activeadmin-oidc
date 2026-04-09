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
