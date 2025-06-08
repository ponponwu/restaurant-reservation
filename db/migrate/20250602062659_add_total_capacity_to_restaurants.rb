class AddTotalCapacityToRestaurants < ActiveRecord::Migration[7.1]
  def change
    add_column :restaurants, :total_capacity, :integer, default: 0, null: false
    add_index :restaurants, :total_capacity
    
    # 為現有餐廳計算並設定容量
    reversible do |dir|
      dir.up do
        Restaurant.find_each do |restaurant|
          capacity = restaurant.restaurant_tables.sum(:max_capacity) || 0
          restaurant.update_column(:total_capacity, capacity)
        end
      end
    end
  end
end
