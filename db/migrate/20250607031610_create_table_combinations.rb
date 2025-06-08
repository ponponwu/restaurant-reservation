class CreateTableCombinations < ActiveRecord::Migration[7.1]
  def change
    create_table :table_combinations do |t|
      t.references :reservation, null: false, foreign_key: true
      t.string :name
      t.text :notes

      t.timestamps
    end
  end
end
