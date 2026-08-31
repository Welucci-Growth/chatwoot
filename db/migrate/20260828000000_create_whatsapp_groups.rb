class CreateWhatsappGroups < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_groups do |t|
      t.references :account, null: false, index: true
      t.string :instance, null: false
      t.string :jid, null: false
      t.string :subject
      t.text :description
      t.integer :size
      t.string :owner
      t.boolean :announce_only, null: false, default: false
      t.boolean :locked, null: false, default: false
      t.datetime :synced_at
      t.timestamps
    end

    add_index :whatsapp_groups, [:account_id, :jid], unique: true
    add_index :whatsapp_groups, [:account_id, :instance]
  end
end
