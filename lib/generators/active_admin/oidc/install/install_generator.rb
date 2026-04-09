# frozen_string_literal: true

require "rails/generators/base"
require "rails/generators/active_record"

module ActiveAdmin
  module Oidc
    module Generators
      # `bin/rails generate active_admin:oidc:install`
      #
      # Produces a working starting point for the host app:
      #
      #   * config/initializers/activeadmin_oidc.rb  (commented template)
      #   * db/migrate/<ts>_add_oidc_to_admin_users.rb
      #   * app/views/active_admin/devise/sessions/new.html.erb (override)
      #
      # Idempotent: running twice is a no-op for all three files (the
      # migration is skipped if an *_add_oidc_to_admin_users.rb file
      # already exists on disk, even with a different timestamp).
      #
      # Refuses to run if the host app is missing an `AdminUser` model
      # or the `devise` / `activeadmin` gems — those are the sharp
      # corners it can't work around, and silently succeeding would
      # produce broken configuration.
      class InstallGenerator < ::Rails::Generators::Base
        include ::Rails::Generators::Migration

        source_root File.expand_path("templates", __dir__)

        desc "Installs activeadmin-oidc into the host Rails app."

        def self.next_migration_number(dirname)
          ::ActiveRecord::Generators::Base.next_migration_number(dirname)
        end

        def verify_host_app!
          unless File.exist?(File.join(destination_root, "app/models/admin_user.rb"))
            raise ::Thor::Error,
                  "activeadmin-oidc: could not find app/models/admin_user.rb — " \
                  "install activeadmin + devise first and make sure the AdminUser " \
                  "model exists."
          end

          gemfile_lock = File.join(destination_root, "Gemfile.lock")
          lock_contents = File.exist?(gemfile_lock) ? File.read(gemfile_lock) : ""

          unless lock_contents.match?(/^\s+devise\b/)
            raise ::Thor::Error,
                  "activeadmin-oidc: devise not found in Gemfile.lock. " \
                  "Add `gem \"devise\"` and run `bundle install` first."
          end

          unless lock_contents.match?(/^\s+activeadmin\b/)
            raise ::Thor::Error,
                  "activeadmin-oidc: activeadmin not found in Gemfile.lock. " \
                  "Add `gem \"activeadmin\"` and run `bundle install` first."
          end
        end

        def create_initializer
          template "initializer.rb.tt", "config/initializers/activeadmin_oidc.rb"
        end

        def create_migration_file
          # Idempotency: if a previous run already produced this
          # migration (any timestamp), do nothing. We never want to
          # stack up duplicate add_column migrations.
          existing = Dir[File.join(destination_root, "db/migrate/*_add_oidc_to_admin_users.rb")]
          return if existing.any?

          @raw_info_type = raw_info_column_type
          migration_template "migration.rb.tt",
                             "db/migrate/add_oidc_to_admin_users.rb"
        end

        def create_view_override
          copy_file "sessions_new.html.erb",
                    "app/views/active_admin/devise/sessions/new.html.erb"
        end

        # Non-blocking: the generator completed successfully, but the
        # host AdminUser may be missing the Devise modules the gem needs.
        # We warn rather than hard-fail because a mid-refactor user may
        # know exactly what they're doing.
        def warn_missing_admin_user_wiring
          admin_user_path = File.join(destination_root, "app/models/admin_user.rb")
          return unless File.exist?(admin_user_path)

          contents = File.read(admin_user_path)

          unless contents.match?(/:omniauthable/)
            say_status :warning,
                       "app/models/admin_user.rb does not include :omniauthable — " \
                       "add `:omniauthable, omniauth_providers: [:oidc]` to your `devise` call.",
                       :yellow
          end

          unless contents.match?(/omniauth_providers\s*:\s*\[\s*:oidc/)
            say_status :warning,
                       "app/models/admin_user.rb does not declare `omniauth_providers: [:oidc]` — " \
                       "the gem's callback controller will not be reachable without it.",
                       :yellow
          end
        end

        # Print a short checklist of the host-app wiring the generator
        # can't do itself. These are the footguns that cost us an hour
        # the first time we wired a fresh demo app: commented-out
        # `authentication_method` / `current_user_method` in the
        # ActiveAdmin initializer, and forgetting to migrate.
        def print_next_steps
          say ""
          say "=" * 60, :green
          say "activeadmin-oidc: next steps", :green
          say "=" * 60, :green
          say <<~STEPS
            1. In config/initializers/active_admin.rb, uncomment:
                 config.authentication_method = :authenticate_admin_user!
                 config.current_user_method   = :current_admin_user
               Without these, /admin is public and the utility nav
               (including the logout button) renders empty.

            2. In app/models/admin_user.rb, make sure the devise call
               includes:
                 :omniauthable, omniauth_providers: [:oidc]

            3. Fill in the generated config/initializers/activeadmin_oidc.rb
               with your issuer and client_id (plus client_secret if you
               are NOT using PKCE public-client mode).

            4. Apply the generated migration:
                 bin/rails db:migrate
          STEPS
          say "=" * 60, :green
        end

        private

        # Postgres gets `jsonb` (fast, indexable), everything else
        # falls back to `:text` so sqlite/mysql hosts aren't left out.
        def raw_info_column_type
          adapter = (ActiveRecord::Base.connection_db_config.adapter rescue "sqlite3").to_s
          adapter.start_with?("postgres") ? ":jsonb" : ":text"
        end
      end
    end
  end
end
