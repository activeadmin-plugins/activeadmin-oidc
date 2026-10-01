# frozen_string_literal: true

require "open3"
require "rbconfig"

# A host that sets `config.omniauth_path_prefix` in its own devise.rb
# fixes that value before the engine's initializer runs, so this suite's
# already-booted app cannot exercise it. The example boots spec/dummy in
# a child process with the value preset, the way such a host would.
RSpec.describe "Host-set Devise.omniauth_path_prefix" do
  let(:boot_script) do
    <<~'RUBY'
      ENV["RAILS_ENV"] = "test"
      require "./spec/dummy/config/application"
      Devise.omniauth_path_prefix = "/sso/auth"
      Dummy::Application.initialize!
      ActiveRecord::Schema.verbose = false
      load "spec/dummy/db/schema.rb"

      OmniAuth.config.test_mode = true
      OmniAuth.config.logger = Logger.new(File::NULL)
      OmniAuth.config.request_validation_phase = ->(_env) { }

      request = ->(method, path) do
        Rails.application.call(Rack::MockRequest.env_for(path, method: method, "HTTP_HOST" => "example.com"))
      end

      _, _, body = request.call("GET", "/admin/login")
      html = +""
      body.each { |chunk| html << chunk }
      action = html[/<form[^>]*action="([^"]+)"/, 1]

      status, headers, = request.call("POST", action)
      puts action, status, headers["Location"]
    RUBY
  end

  it "points the login form and the middleware at the host's prefix" do
    out, err, status = Open3.capture3(RbConfig.ruby, "-e", boot_script,
                                      chdir: File.expand_path("../..", __dir__))
    expect(status).to be_success, err

    action, post_status, location = out.lines.last(3).map(&:chomp)
    expect(action).to eq("/sso/auth/oidc")
    expect(post_status).to eq("302")
    expect(location).to eq("http://example.com/sso/auth/oidc/callback")
  end
end
