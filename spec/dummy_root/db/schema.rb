# frozen_string_literal: true

ActiveRecord::Schema[7.2].define(version: 0) do
  create_table :admin_users, force: :cascade do |t|
    t.string   :email
    t.string   :username
    t.string   :provider
    t.string   :uid
    t.text     :oidc_raw_info
    t.string   :department
    t.boolean  :enabled, default: true
    t.timestamps
  end

  add_index :admin_users, :email, unique: true
  add_index :admin_users, %i[provider uid], unique: true,
                                            where: "provider IS NOT NULL AND uid IS NOT NULL",
                                            name: "index_admin_users_on_provider_and_uid"
end
