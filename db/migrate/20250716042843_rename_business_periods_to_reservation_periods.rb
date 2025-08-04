class RenameBusinessPeriodsToReservationPeriods < ActiveRecord::Migration[8.0]
  def change
    rename_table :business_periods, :reservation_periods
    
    # 更新外鍵名稱
    rename_column :reservations, :business_period_id, :reservation_period_id
    rename_column :reservation_slots, :business_period_id, :reservation_period_id
    
    # 更新索引名稱
    if index_exists?(:reservation_periods, [:restaurant_id, :date], name: 'index_business_periods_on_restaurant_date')
      rename_index :reservation_periods, 'index_business_periods_on_restaurant_date', 'index_reservation_periods_on_restaurant_date'
    end
    
    if index_exists?(:reservation_periods, [:restaurant_id, :weekday], name: 'index_business_periods_on_restaurant_weekday')
      rename_index :reservation_periods, 'index_business_periods_on_restaurant_weekday', 'index_reservation_periods_on_restaurant_weekday'
    end
    
    if index_exists?(:reservation_periods, :operation_mode, name: 'index_business_periods_on_operation_mode')
      rename_index :reservation_periods, 'index_business_periods_on_operation_mode', 'index_reservation_periods_on_operation_mode'
    end
    
    if index_exists?(:reservation_periods, :restaurant_id, name: 'index_business_periods_on_restaurant_id')
      rename_index :reservation_periods, 'index_business_periods_on_restaurant_id', 'index_reservation_periods_on_restaurant_id'
    end
    
    # 更新外鍵約束名稱 (如果存在)
    if foreign_key_exists?(:reservations, :reservation_periods, column: :reservation_period_id)
      remove_foreign_key :reservations, :reservation_periods, column: :reservation_period_id
      add_foreign_key :reservations, :reservation_periods, column: :reservation_period_id
    end
    
    if foreign_key_exists?(:reservation_slots, :reservation_periods, column: :reservation_period_id)
      remove_foreign_key :reservation_slots, :reservation_periods, column: :reservation_period_id  
      add_foreign_key :reservation_slots, :reservation_periods, column: :reservation_period_id
    end
  end
end