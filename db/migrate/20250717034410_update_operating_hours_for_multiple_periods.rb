class UpdateOperatingHoursForMultiplePeriods < ActiveRecord::Migration[8.0]
  def change
    # 移除舊的唯一約束（如果存在）
    remove_index :operating_hours, [:restaurant_id, :weekday], if_exists: true
    
    # 添加新欄位支援多時段
    add_column :operating_hours, :period_name, :string, default: '預設時段'
    add_column :operating_hours, :sort_order, :integer, default: 1
    
    # 更新現有記錄
    reversible do |dir|
      dir.up do
        # 為現有記錄設定預設值
        OperatingHour.update_all(period_name: '預設時段', sort_order: 1)
      end
    end
    
    # 添加新的索引
    add_index :operating_hours, [:restaurant_id, :weekday, :sort_order], 
              name: 'index_operating_hours_on_restaurant_weekday_sort'
  end
end
