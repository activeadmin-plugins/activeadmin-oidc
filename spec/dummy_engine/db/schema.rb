# frozen_string_literal: true

ActiveRecord::Schema[7.2].define(version: 0) do
  create_table :admin_users, force: :cascade do |t|
    t.string   :email
    t.string   :username
    t.string   :provider
    t.string   :uid
    t.text     :oidc_raw_info
    t.timestamps
  end

  add_index :admin_users, :email, unique: true
end
