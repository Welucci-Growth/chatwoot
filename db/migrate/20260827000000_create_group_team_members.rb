class CreateGroupTeamMembers < ActiveRecord::Migration[7.1]
  def change
    create_table :group_team_members do |t|
      t.references :account, null: false, index: true
      t.string :phone_number, null: false
      t.string :name
      t.string :source, null: false, default: 'manual'
      t.timestamps
    end

    add_index :group_team_members, [:account_id, :phone_number], unique: true
  end
end
