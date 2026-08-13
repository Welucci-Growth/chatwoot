class CreateTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :tasks do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :task_board, null: false, foreign_key: true, index: true
      t.references :task_column, null: false, foreign_key: true, index: true
      t.references :assignee, foreign_key: { to_table: :users }, index: true
      t.references :contact, index: true
      t.references :conversation, index: true
      t.string :title, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.datetime :due_on
      t.jsonb :custom_attributes, default: {}

      t.timestamps
    end
  end
end
