class AddCancellationTokenToReservations < ActiveRecord::Migration[7.1]
  def change
    add_column :reservations, :cancellation_token, :string
    add_index :reservations, :cancellation_token, unique: true
    
    # 為現有的訂位記錄生成取消令牌
    reversible do |dir|
      dir.up do
        Reservation.find_each do |reservation|
          reservation.update_column(:cancellation_token, SecureRandom.urlsafe_base64(32))
        end
      end
    end
    
    # 設置為 NOT NULL（在設置完預設值後）
    change_column_null :reservations, :cancellation_token, false
  end
end 