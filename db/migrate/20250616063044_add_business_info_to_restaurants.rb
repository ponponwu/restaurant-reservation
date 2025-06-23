class AddBusinessInfoToRestaurants < ActiveRecord::Migration[7.1]
  def change
    add_column :restaurants, :reminder_notes, :text
    add_column :restaurants, :business_name, :string
    add_column :restaurants, :tax_id, :string
  end
end
