class CreateTaskColumns < ActiveRecord::Migration[7.1]
  def change
    create_table :task_columns do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :task_board, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.string :color
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
