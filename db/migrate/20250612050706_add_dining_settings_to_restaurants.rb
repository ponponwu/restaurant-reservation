class AddDiningSettingsToRestaurants < ActiveRecord::Migration[7.1]
  def change
    add_column :restaurants, :unlimited_dining_time, :boolean, default: false, null: false, comment: '是否為無限用餐時間'
    add_column :restaurants, :default_dining_duration_minutes, :integer, default: 120, null: true, comment: '預設用餐時間（分鐘）'
    add_column :restaurants, :allow_table_combinations, :boolean, default: true, null: false, comment: '是否允許併桌'
    add_column :restaurants, :max_combination_tables, :integer, default: 3, null: false, comment: '最大併桌數量'
    add_column :restaurants, :buffer_time_minutes, :integer, default: 15, null: false, comment: '緩衝時間（分鐘）'
    
    add_index :restaurants, :unlimited_dining_time
    add_index :restaurants, :allow_table_combinations
  end
end
