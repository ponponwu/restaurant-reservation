class AddSpecialDateFieldsToReservationPeriods < ActiveRecord::Migration[8.0]
  def change
    add_reference :reservation_periods, :special_reservation_date, null: true, foreign_key: true
    add_column :reservation_periods, :custom_period_index, :integer, null: true
    add_column :reservation_periods, :is_special_date_period, :boolean, default: false, null: false
    
    # 新增索引以提升查詢效能
    add_index :reservation_periods, [:special_reservation_date_id, :custom_period_index], 
              name: 'index_reservation_periods_on_special_date_and_period_index'
    add_index :reservation_periods, :is_special_date_period
  end
end
