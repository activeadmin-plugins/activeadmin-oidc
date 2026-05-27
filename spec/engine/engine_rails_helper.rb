# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require "spec_helper"
require_relative "../dummy_engine/config/environment"

abort("Rails not in test mode") if Rails.env.production?

require "rspec/rails"
require "webmock/rspec"
require "capybara/rspec"

ActiveRecord::Schema.verbose = false
load File.expand_path("../dummy_engine/db/schema.rb", __dir__)

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end

OmniAuth.config.test_mode = true
OmniAuth.config.logger = Logger.new(File::NULL)
OmniAuth.config.request_validation_phase = ->(_env) { }
OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning = true if OmniAuth.config.respond_to?(:silence_get_warning=)
