class CreateTaskBoards < ActiveRecord::Migration[7.1]
  def change
    create_table :task_boards do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :owner, foreign_key: { to_table: :users }, index: true
      t.string :name, null: false
      t.integer :visibility, null: false, default: 0
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
