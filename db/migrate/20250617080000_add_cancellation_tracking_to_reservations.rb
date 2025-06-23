class AddCancellationTrackingToReservations < ActiveRecord::Migration[7.1]
  def change
    add_column :reservations, :cancelled_by, :string
    add_column :reservations, :cancelled_at, :datetime
    add_column :reservations, :cancellation_reason, :text
    add_column :reservations, :cancellation_method, :string
    
    add_index :reservations, :cancelled_at
    add_index :reservations, :cancelled_by
  end
end 