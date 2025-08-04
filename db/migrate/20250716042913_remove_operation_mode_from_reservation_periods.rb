class RemoveOperationModeFromReservationPeriods < ActiveRecord::Migration[8.0]
  def change
    # 移除 operation_mode 索引
    if index_exists?(:reservation_periods, :operation_mode, name: 'index_reservation_periods_on_operation_mode')
      remove_index :reservation_periods, name: 'index_reservation_periods_on_operation_mode'
    end
    
    # 移除 operation_mode 欄位
    remove_column :reservation_periods, :operation_mode, :string
  end
end