# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/active_admin/oidc/install/install_generator"

# The install generator is what a host app runs once:
#
#   bundle add activeadmin-oidc
#   bin/rails generate active_admin:oidc:install
#
# It must produce a working, editable starting point — initializer with
# sample `on_login` snippets, a migration adding
# `provider`/`uid`/`oidc_raw_info` + a unique index to `admin_users`,
# and a published login view override. It must be
# idempotent (running twice does nothing bad) and refuse to run if the
# host app doesn't have `AdminUser` or `devise`/`activeadmin`.
RSpec.describe ActiveAdmin::Oidc::Generators::InstallGenerator do
  let(:destination_root) { File.expand_path("../../tmp/generator_test", __dir__) }

  before do
    FileUtils.rm_rf(destination_root)
    FileUtils.mkdir_p(destination_root)
    # Stand up a minimal fake host-app tree so the generator can find
    # config/routes.rb, config/initializers, db/migrate, Gemfile.lock
    # and the AdminUser model it needs to refuse-to-run without.
    FileUtils.mkdir_p(File.join(destination_root, "config/initializers"))
    FileUtils.mkdir_p(File.join(destination_root, "db/migrate"))
    FileUtils.mkdir_p(File.join(destination_root, "app/models"))
    File.write(
      File.join(destination_root, "config/routes.rb"),
      <<~RUBY
        Rails.application.routes.draw do
          ActiveAdmin.routes(self)
        end
      RUBY
    )
    File.write(
      File.join(destination_root, "app/models/admin_user.rb"),
      "class AdminUser < ApplicationRecord; end\n"
    )
    File.write(
      File.join(destination_root, "Gemfile.lock"),
      <<~LOCK
        GEM
          specs:
            devise (5.0.3)
            activeadmin (3.5.1)
      LOCK
    )
  end

  def run_generator(args = [])
    # Instantiate directly rather than going through `start` so that
    # `Thor::Error` raised in preflight propagates to the spec instead
    # of being caught by Thor's CLI wrapper. Redirect $stdout so the
    # "create file" log lines don't pollute rspec output, but capture
    # it so tests can assert on warnings and next-steps output.
    generator = described_class.new(args, [], destination_root: destination_root)
    orig_stdout = $stdout
    captured = StringIO.new
    $stdout = captured
    begin
      generator.invoke_all
    ensure
      $stdout = orig_stdout
    end
    captured.string
  end

  describe "initializer" do
    before { run_generator }

    let(:initializer) do
      File.read(File.join(destination_root, "config/initializers/activeadmin_oidc.rb"))
    end

    it "creates the initializer at config/initializers/activeadmin_oidc.rb" do
      expect(File).to exist(
        File.join(destination_root, "config/initializers/activeadmin_oidc.rb")
      )
    end

    it "contains an ActiveAdmin::Oidc.configure block" do
      expect(initializer).to include("ActiveAdmin::Oidc.configure do |c|")
    end

    it "includes commented-out ENV reads for issuer/client_id/client_secret" do
      expect(initializer).to match(/#\s*c\.issuer\s*=\s*ENV/)
      expect(initializer).to match(/#\s*c\.client_id\s*=\s*ENV/)
      expect(initializer).to match(/#\s*c\.client_secret\s*=\s*ENV/)
    end

    it "includes a sample on_login snippet for Zitadel nested roles claim" do
      expect(initializer).to include("urn:zitadel:iam:org:project:roles")
    end

    it "includes a sample on_login snippet for a department-style assignment" do
      expect(initializer).to match(/department/i)
    end
  end

  describe "migration" do
    before { run_generator }

    let(:migration_path) do
      Dir[File.join(destination_root, "db/migrate/*_add_oidc_to_admin_users.rb")].first
    end

    let(:migration) { File.read(migration_path) }

    it "creates a timestamped migration adding oidc columns to admin_users" do
      expect(migration_path).not_to be_nil
    end

    it "adds provider, uid, and oidc_raw_info columns" do
      expect(migration).to match(/add_column\s+:admin_users,\s*:provider,\s*:string/)
      expect(migration).to match(/add_column\s+:admin_users,\s*:uid,\s*:string/)
      expect(migration).to match(/add_column\s+:admin_users,\s*:oidc_raw_info/)
    end

    it "does not add any authorization column (no :role, :roles, :department)" do
      expect(migration).not_to match(/:roles?\b/)
      expect(migration).not_to match(/:department/)
    end

    it "adds a unique index on (provider, uid)" do
      expect(migration).to match(
        /add_index\s+:admin_users,\s*\[:provider,\s*:uid\],\s*unique:\s*true/
      )
    end
  end

  describe "login view override" do
    before { run_generator }

    let(:published_view) do
      File.read(
        File.join(destination_root, "app/views/active_admin/devise/sessions/new.html.erb")
      )
    end

    it "publishes app/views/active_admin/devise/sessions/new.html.erb" do
      expect(File).to exist(
        File.join(destination_root, "app/views/active_admin/devise/sessions/new.html.erb")
      )
    end

    # The template is copied verbatim (copy_file, not template), so an
    # escaped `<%%=` would survive into the host app and render as
    # literal `<%= ... %>` text on the login page.
    it "publishes real ERB tags, not generator-escaped ones" do
      expect(published_view).not_to include("<%%")
      expect(published_view).to include("<%=")
    end

    it "includes the stub login block so the dev button still renders" do
      expect(published_view).to include("activeadmin_oidc_stub_login_enabled?")
      expect(published_view).to include("activeadmin_oidc_stub_login_path")
    end

    it "posts the SSO button through the helper rather than a hardcoded path" do
      expect(published_view).to include("activeadmin_oidc_sso_login_path")
    end
  end

  describe "idempotency" do
    it "does not duplicate the initializer when run twice" do
      run_generator
      initializer_path = File.join(destination_root, "config/initializers/activeadmin_oidc.rb")
      first = File.read(initializer_path)

      run_generator
      second = File.read(initializer_path)

      expect(second).to eq(first)
    end

    it "does not create a second migration when run twice" do
      run_generator
      first_migrations = Dir[File.join(destination_root, "db/migrate/*_add_oidc_to_admin_users.rb")]
      expect(first_migrations.size).to eq(1)

      run_generator
      second_migrations = Dir[File.join(destination_root, "db/migrate/*_add_oidc_to_admin_users.rb")]
      expect(second_migrations.size).to eq(1)
    end
  end

  describe "preflight checks" do
    it "aborts with a clear error if AdminUser model is missing" do
      FileUtils.rm(File.join(destination_root, "app/models/admin_user.rb"))

      expect { run_generator }.to raise_error(Thor::Error, /AdminUser/)
    end

    it "aborts with a clear error if devise is not in Gemfile.lock" do
      File.write(
        File.join(destination_root, "Gemfile.lock"),
        "GEM\n  specs:\n    activeadmin (3.5.1)\n"
      )

      expect { run_generator }.to raise_error(Thor::Error, /devise/)
    end

    it "aborts with a clear error if activeadmin is not in Gemfile.lock" do
      File.write(
        File.join(destination_root, "Gemfile.lock"),
        "GEM\n  specs:\n    devise (5.0.3)\n"
      )

      expect { run_generator }.to raise_error(Thor::Error, /activeadmin/)
    end
  end

  describe "warnings for AdminUser devise setup" do
    # These are soft checks: the generator still runs to completion,
    # but prints a warning pointing the user at the missing wiring.
    # Hard-failing would be too aggressive — the user may be mid-refactor
    # and know what they're doing.

    it "warns when AdminUser does not include :omniauthable" do
      File.write(
        File.join(destination_root, "app/models/admin_user.rb"),
        <<~RUBY
          class AdminUser < ApplicationRecord
            devise :database_authenticatable, :rememberable
          end
        RUBY
      )

      output = run_generator
      expect(output).to match(/:omniauthable/)
      expect(output).to match(/admin_user\.rb/i)
    end

    it "warns when AdminUser does not declare omniauth_providers: [:oidc]" do
      File.write(
        File.join(destination_root, "app/models/admin_user.rb"),
        <<~RUBY
          class AdminUser < ApplicationRecord
            devise :database_authenticatable, :omniauthable
          end
        RUBY
      )

      output = run_generator
      expect(output).to match(/omniauth_providers.*:oidc/)
    end

    it "does NOT warn when AdminUser is already wired for oidc omniauth" do
      File.write(
        File.join(destination_root, "app/models/admin_user.rb"),
        <<~RUBY
          class AdminUser < ApplicationRecord
            devise :database_authenticatable,
                   :omniauthable, omniauth_providers: [:oidc]
          end
        RUBY
      )

      output = run_generator
      expect(output).not_to match(/warning.*omniauthable/i)
      expect(output).not_to match(/warning.*omniauth_providers/i)
    end
  end

  describe "post-install next-steps message" do
    it "prints a next-steps section after a successful run" do
      output = run_generator
      expect(output).to match(/next steps/i)
    end

    it "reminds the host to uncomment authentication_method in active_admin.rb" do
      output = run_generator
      expect(output).to include("authentication_method")
      expect(output).to include(":authenticate_admin_user!")
    end

    it "reminds the host to uncomment current_user_method in active_admin.rb" do
      output = run_generator
      expect(output).to include("current_user_method")
      expect(output).to include(":current_admin_user")
    end

    it "reminds the host to run the generated migration" do
      output = run_generator
      expect(output).to match(/db:migrate|rails\s+db:migrate/)
    end

    it "reminds the host to set AdminUser :omniauthable with omniauth_providers: [:oidc]" do
      output = run_generator
      expect(output).to include("omniauth_providers: [:oidc]")
    end
  end
end
