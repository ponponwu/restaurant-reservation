class AddConcurrencyControlsToReservations < ActiveRecord::Migration[7.1]
  def change
    # 新增複合唯一索引以防止同一桌位同一時間被重複預約
    # 只對 active 狀態的訂位進行限制（排除已取消和未出席的訂位）
    add_index :reservations, 
              [:table_id, :reservation_datetime, :restaurant_id], 
              unique: true,
              where: "status NOT IN ('cancelled', 'no_show')",
              name: 'index_reservations_on_table_datetime_restaurant_active'
    
    # 新增複合索引來加速併發檢查查詢
    add_index :reservations,
              [:restaurant_id, :reservation_datetime, :status],
              name: 'index_reservations_on_restaurant_datetime_status'
    
    # 新增索引來加速手機號碼限制檢查
    add_index :reservations,
              [:restaurant_id, :customer_phone, :status, :reservation_datetime],
              name: 'index_reservations_on_restaurant_phone_status_datetime'
    
    # 新增版本控制欄位用於樂觀鎖定
    add_column :reservations, :lock_version, :integer, default: 0, null: false
    
    # 新增併發處理標記
    add_column :reservations, :allocation_token, :string, limit: 36
    add_index :reservations, :allocation_token, unique: true, where: "allocation_token IS NOT NULL"
  end
end