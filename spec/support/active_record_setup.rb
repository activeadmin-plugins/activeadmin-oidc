# frozen_string_literal: true

require "active_record"
require "sqlite3"

# In-memory SQLite for unit specs that need ActiveRecord without spinning up
# a full Rails dummy app.
ActiveRecord::Base.establish_connection(
  adapter:  "sqlite3",
  database: ":memory:"
)

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :admin_users, force: true do |t|
    t.string :email
    t.string :username
    t.string :provider
    t.string :uid
    t.text   :oidc_raw_info
    t.string :department
    t.timestamps
  end

  add_index :admin_users, %i[provider uid], unique: true,
                                            where: "provider IS NOT NULL AND uid IS NOT NULL",
                                            name: "index_admin_users_on_provider_and_uid"
end

# Minimal AdminUser stand-in used by UserProvisioner specs. The real host app
# brings its own model; the gem only needs the columns provisioner touches.
class AdminUser < ActiveRecord::Base
  validates :email, presence: true
  serialize :oidc_raw_info, coder: JSON
end
