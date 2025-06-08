class AddCanCombineToRestaurantTables < ActiveRecord::Migration[7.1]
  def change
    add_column :restaurant_tables, :can_combine, :boolean, default: false, null: false
  end
end
