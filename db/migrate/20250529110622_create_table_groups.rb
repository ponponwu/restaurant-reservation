class CreateTableGroups < ActiveRecord::Migration[7.1]
  def change
    create_table :table_groups do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.integer :sort_order
      t.boolean :active

      t.timestamps
    end
  end
end
