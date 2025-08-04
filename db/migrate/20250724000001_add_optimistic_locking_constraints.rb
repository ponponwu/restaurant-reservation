class AddOptimisticLockingConstraints < ActiveRecord::Migration[8.0]
  def up
    # 防止同一桌位在重疊時間被重複預訂
    # 使用 restaurant_id, table_id, 日期, 小時, 分鐘作為唯一約束
    execute <<-SQL
      CREATE UNIQUE INDEX idx_reservations_table_time_conflict 
      ON reservations (restaurant_id, table_id, DATE(reservation_datetime), 
                      EXTRACT(hour FROM reservation_datetime), 
                      EXTRACT(minute FROM reservation_datetime))
      WHERE status IN ('confirmed', 'pending') 
      AND table_id IS NOT NULL;
    SQL
    
    # 防止同一手機號碼在同一餐廳的同一時段重複預訂
    execute <<-SQL
      CREATE UNIQUE INDEX idx_reservations_phone_time_conflict
      ON reservations (restaurant_id, customer_phone, reservation_datetime)
      WHERE status IN ('confirmed', 'pending')
      AND customer_phone IS NOT NULL;
    SQL
    
    Rails.logger.info "樂觀鎖約束索引建立完成"
  end
  
  def down
    execute "DROP INDEX IF EXISTS idx_reservations_table_time_conflict;"
    execute "DROP INDEX IF EXISTS idx_reservations_phone_time_conflict;"
    
    Rails.logger.info "樂觀鎖約束索引已移除"
  end
end