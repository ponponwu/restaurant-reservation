class RemoveReservationDeadlineFromReservationSlots < ActiveRecord::Migration[8.0]
  def change
    remove_column :reservation_slots, :reservation_deadline, :integer, default: 60
  end
end
