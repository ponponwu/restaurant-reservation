class AddAdminOverrideToReservations < ActiveRecord::Migration[7.1]
  def change
    add_column :reservations, :admin_override, :boolean, default: false, null: false, comment: "是否為管理員強制建立（無視容量限制）"
    add_index :reservations, :admin_override
  end
end
