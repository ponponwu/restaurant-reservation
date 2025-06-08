class CreateTables < ActiveRecord::Migration[7.1]
  def change
    create_table :tables do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.references :table_group, null: true, foreign_key: true
      t.string :table_number
      t.integer :capacity
      t.integer :min_capacity
      t.integer :max_capacity
      t.string :table_type
      t.integer :sort_order
      t.string :status
      t.json :metadata

      t.timestamps
    end
    
    add_index :tables, [:restaurant_id, :table_number], unique: true
    add_index :tables, :status
    add_index :tables, :capacity
    add_index :tables, [:restaurant_id, :table_group_id]
  end
end
