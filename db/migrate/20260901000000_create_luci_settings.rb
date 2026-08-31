class CreateLuciSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :luci_settings do |t|
      t.references :account, null: false, index: { unique: true }
      t.text :system_prompt
      t.text :knowledge
      t.string :model, null: false, default: 'claude-haiku-4-5'
      t.string :required_label, null: false, default: 'luci'
      t.boolean :enabled, null: false, default: false
      t.timestamps
    end
  end
end
