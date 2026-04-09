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
