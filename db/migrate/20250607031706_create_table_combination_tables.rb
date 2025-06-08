class CreateTableCombinationTables < ActiveRecord::Migration[7.1]
  def change
    create_table :table_combination_tables do |t|
      t.references :table_combination, null: false, foreign_key: true
      t.references :restaurant_table, null: false, foreign_key: true

      t.timestamps
    end
  end
end
