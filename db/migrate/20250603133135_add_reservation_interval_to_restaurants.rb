class AddReservationIntervalToRestaurants < ActiveRecord::Migration[7.1]
  def change
    add_column :restaurants, :reservation_interval_minutes, :integer, null: false, default: 30
    
    # 為現有餐廳設定預設值
    reversible do |dir|
      dir.up do
        execute "UPDATE restaurants SET reservation_interval_minutes = 30 WHERE reservation_interval_minutes IS NULL"
      end
    end
  end
end
