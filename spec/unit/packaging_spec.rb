# frozen_string_literal: true

require "spec_helper"

# These are packaging-correctness tests: they verify that the gem's
# main entry point wires in all the runtime glue a host app needs after
# a plain `gem "activeadmin-oidc"` + `Bundler.require`.
#
# Why text-level? `Bundler.require` only auto-requires gems listed in
# the Gemfile, not the transitive dependencies pulled in via our
# gemspec. So a host that does `gem "activeadmin-oidc"` will NOT
# auto-load `omniauth-rails_csrf_protection` — our gem has to require
# it explicitly. The gem's own Gemfile uses `gemspec` which DOES load
# all runtime deps, so a behavior test inside this suite would always
# pass and silently miss regressions. Parsing the entry-point file
# catches that.
RSpec.describe "packaging" do
  let(:entry_point_path) do
    File.expand_path("../../lib/activeadmin-oidc.rb", __dir__)
  end

  let(:entry_point_source) { File.read(entry_point_path) }

  it "requires omniauth/rails_csrf_protection so its railtie registers before the app boots" do
    expect(entry_point_source).to match(/^require\s+["']omniauth\/rails_csrf_protection["']/)
  end

  it "loads OmniAuth::RailsCsrfProtection::TokenVerifier at require time" do
    # Second guard: even if the grep above drifted, the constant must
    # exist by the time the gem is loaded.
    require "activeadmin-oidc"
    expect(defined?(OmniAuth::RailsCsrfProtection::TokenVerifier))
      .to eq("constant")
  end
end
