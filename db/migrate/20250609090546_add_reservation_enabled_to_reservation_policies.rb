class AddReservationEnabledToReservationPolicies < ActiveRecord::Migration[7.1]
  def change
    add_column :reservation_policies, :reservation_enabled, :boolean, default: true, null: false, comment: '是否啟用線上訂位功能'
  end
end
