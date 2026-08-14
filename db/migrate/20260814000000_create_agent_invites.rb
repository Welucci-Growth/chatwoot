class CreateAgentInvites < ActiveRecord::Migration[7.1]
  def change
    create_table :agent_invites do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :inviter, foreign_key: { to_table: :users }, index: true
      t.references :team, foreign_key: true, index: true
      t.integer :role, null: false, default: 0
      t.string :token, null: false
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end
    add_index :agent_invites, :token, unique: true
  end
end
