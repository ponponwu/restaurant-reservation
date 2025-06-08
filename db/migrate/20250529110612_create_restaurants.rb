class CreateRestaurants < ActiveRecord::Migration[7.1]
  def change
    create_table :restaurants do |t|
      t.string :name
      t.text :description
      t.string :phone
      t.text :address
      t.json :settings
      t.boolean :active, default: true

      t.timestamps
    end
    
    add_index :restaurants, :name
    add_index :restaurants, :active
  end
end
