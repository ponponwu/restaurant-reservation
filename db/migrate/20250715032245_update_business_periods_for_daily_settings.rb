class UpdateBusinessPeriodsForDailySettings < ActiveRecord::Migration[8.0]
  def up
    # 移除週別設定，改為每日設定
    remove_column :business_periods, :days_of_week_mask, :integer
    
    # 新增每日設定欄位 (先允許 NULL，稍後更新)
    add_column :business_periods, :weekday, :integer, null: true, comment: '星期幾 (0=日, 1=一, ..., 6=六)'
    add_column :business_periods, :date, :date, null: true, comment: '特定日期設定 (覆蓋週別設定)'
    add_column :business_periods, :reservation_interval_minutes, :integer, default: 30, null: true, comment: '該時段的預約間隔分鐘數'
    add_column :business_periods, :operation_mode, :string, default: 'custom_hours', null: true, comment: '營業模式'
    
    # 新增索引
    add_index :business_periods, [:restaurant_id, :weekday], name: 'index_business_periods_on_restaurant_weekday'
    add_index :business_periods, [:restaurant_id, :date], name: 'index_business_periods_on_restaurant_date'
    add_index :business_periods, :operation_mode
    
    
    
    # 設定 NOT NULL 約束
    change_column_null :business_periods, :weekday, false
    change_column_null :business_periods, :reservation_interval_minutes, false
    change_column_null :business_periods, :operation_mode, false
  end

  def down
    # 恢復原有結構
    add_column :business_periods, :days_of_week_mask, :integer, default: 0
    
    remove_index :business_periods, name: 'index_business_periods_on_restaurant_weekday'
    remove_index :business_periods, name: 'index_business_periods_on_restaurant_date'
    remove_index :business_periods, :operation_mode
    
    remove_column :business_periods, :weekday
    remove_column :business_periods, :date
    remove_column :business_periods, :reservation_interval_minutes
    remove_column :business_periods, :operation_mode
  end
end