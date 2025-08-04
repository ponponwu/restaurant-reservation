class RemoveBufferTimeFromReservationPolicies < ActiveRecord::Migration[8.0]
  def up
    remove_column :reservation_policies, :buffer_time_minutes
  end

  def down
    add_column :reservation_policies, :buffer_time_minutes, :integer, 
               default: 15, null: false, 
               comment: '緩衝時間（分鐘）'
  end
end
