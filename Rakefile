# frozen_string_literal: true

require "bundler/gem_tasks"

begin
  require "rspec/core/rake_task"

  # Default spec suite — boots spec/dummy/ (main-app OIDC-only setup).
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.exclude_pattern = "spec/{engine,isolated,dummy_engine,dummy_isolated}/**/*"
  end

  namespace :spec do
    # Each variant below boots a different dummy Rails app and therefore
    # must run in its own process. CI invokes them as separate steps;
    # locally `rake spec:all` runs them sequentially via `sh`.
    desc "Run engine-mounted-Devise specs (boots spec/dummy_engine/)"
    task :engine do
      sh "bundle exec rspec --options /dev/null --require spec_helper -I spec/engine spec/engine"
    end

    desc "Run isolated-engine specs (boots spec/dummy_isolated/)"
    task :isolated do
      sh "bundle exec rspec --options /dev/null --require spec_helper -I spec/isolated spec/isolated"
    end

    desc "Run every spec suite (default + engine + isolated)"
    task all: [:spec, :engine, :isolated]
  end

  task default: :spec
rescue LoadError
  # rspec not available
end
