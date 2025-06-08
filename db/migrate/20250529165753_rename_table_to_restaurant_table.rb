class RenameTableToRestaurantTable < ActiveRecord::Migration[7.1]
  def change
    rename_table :tables, :restaurant_tables
  end
end
