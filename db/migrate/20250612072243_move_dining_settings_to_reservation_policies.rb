class MoveDiningSettingsToReservationPolicies < ActiveRecord::Migration[7.0]
  def up
    # 1. 在 reservation_policies 表中新增用餐設定欄位
    add_column :reservation_policies, :unlimited_dining_time, :boolean, 
               default: false, null: false, comment: '是否為無限用餐時間'
    add_column :reservation_policies, :default_dining_duration_minutes, :integer, 
               default: 120, comment: '預設用餐時間（分鐘）'
    add_column :reservation_policies, :buffer_time_minutes, :integer, 
               default: 15, null: false, comment: '緩衝時間（分鐘）'
    add_column :reservation_policies, :allow_table_combinations, :boolean, 
               default: true, null: false, comment: '是否允許併桌'
    add_column :reservation_policies, :max_combination_tables, :integer, 
               default: 3, null: false, comment: '最大併桌數量'
    
    # 2. 新增索引
    add_index :reservation_policies, :unlimited_dining_time
    add_index :reservation_policies, :allow_table_combinations
    
    # 3. 數據遷移：將現有的餐廳設定值複製到對應的訂位政策中
    Restaurant.includes(:reservation_policy).find_each do |restaurant|
      policy = restaurant.reservation_policy || restaurant.create_reservation_policy!
      
      policy.update_columns(
        unlimited_dining_time: restaurant.unlimited_dining_time || false,
        default_dining_duration_minutes: restaurant.default_dining_duration_minutes || 120,
        buffer_time_minutes: restaurant.buffer_time_minutes || 15,
        allow_table_combinations: restaurant.allow_table_combinations.nil? ? true : restaurant.allow_table_combinations,
        max_combination_tables: restaurant.max_combination_tables || 3
      )
    end
    
    # 4. 從 restaurants 表中移除這些欄位
    remove_index :restaurants, :unlimited_dining_time if index_exists?(:restaurants, :unlimited_dining_time)
    remove_index :restaurants, :allow_table_combinations if index_exists?(:restaurants, :allow_table_combinations)
    
    remove_column :restaurants, :unlimited_dining_time
    remove_column :restaurants, :default_dining_duration_minutes
    remove_column :restaurants, :buffer_time_minutes
    remove_column :restaurants, :allow_table_combinations
    remove_column :restaurants, :max_combination_tables
  end

  def down
    # 1. 在 restaurants 表中重新新增這些欄位
    add_column :restaurants, :unlimited_dining_time, :boolean, 
               default: false, null: false, comment: '是否為無限用餐時間'
    add_column :restaurants, :default_dining_duration_minutes, :integer, 
               default: 120, comment: '預設用餐時間（分鐘）'
    add_column :restaurants, :buffer_time_minutes, :integer, 
               default: 15, null: false, comment: '緩衝時間（分鐘）'
    add_column :restaurants, :allow_table_combinations, :boolean, 
               default: true, null: false, comment: '是否允許併桌'
    add_column :restaurants, :max_combination_tables, :integer, 
               default: 3, null: false, comment: '最大併桌數量'
    
    # 2. 數據遷移：將訂位政策的值複製回餐廳
    Restaurant.includes(:reservation_policy).find_each do |restaurant|
      next unless restaurant.reservation_policy
      
      policy = restaurant.reservation_policy
      restaurant.update_columns(
        unlimited_dining_time: policy.unlimited_dining_time || false,
        default_dining_duration_minutes: policy.default_dining_duration_minutes || 120,
        buffer_time_minutes: policy.buffer_time_minutes || 15,
        allow_table_combinations: policy.allow_table_combinations.nil? ? true : policy.allow_table_combinations,
        max_combination_tables: policy.max_combination_tables || 3
      )
    end
    
    # 3. 新增索引
    add_index :restaurants, :unlimited_dining_time
    add_index :restaurants, :allow_table_combinations
    
    # 4. 從 reservation_policies 表中移除這些欄位
    remove_index :reservation_policies, :unlimited_dining_time if index_exists?(:reservation_policies, :unlimited_dining_time)
    remove_index :reservation_policies, :allow_table_combinations if index_exists?(:reservation_policies, :allow_table_combinations)
    
    remove_column :reservation_policies, :unlimited_dining_time
    remove_column :reservation_policies, :default_dining_duration_minutes
    remove_column :reservation_policies, :buffer_time_minutes
    remove_column :reservation_policies, :allow_table_combinations
    remove_column :reservation_policies, :max_combination_tables
  end
end
