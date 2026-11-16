class AddAccessProfileToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :access_profile, :string
  end
end
