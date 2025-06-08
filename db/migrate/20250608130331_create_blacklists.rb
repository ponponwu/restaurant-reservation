class CreateBlacklists < ActiveRecord::Migration[7.1]
  def change
    create_table :blacklists do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.string :customer_name, null: false
      t.string :customer_phone, null: false
      t.text :reason
      t.string :added_by_name
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :blacklists, [:restaurant_id, :customer_phone], unique: true
    add_index :blacklists, :customer_phone
    add_index :blacklists, :active
  end
end
