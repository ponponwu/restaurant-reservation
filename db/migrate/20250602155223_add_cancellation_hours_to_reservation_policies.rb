class AddCancellationHoursToReservationPolicies < ActiveRecord::Migration[7.1]
  def change
    add_column :reservation_policies, :cancellation_hours, :integer, default: 24
  end
end
