class RemovePriorityFromSpecialReservationDates < ActiveRecord::Migration[7.1]
  def up
    # Remove priority index first if it exists
    remove_index :special_reservation_dates, :priority if index_exists?(:special_reservation_dates, :priority)
    
    # Then remove the column
    remove_column :special_reservation_dates, :priority
  end

  def down
    # Add column back with default value
    add_column :special_reservation_dates, :priority, :integer, default: 0, null: false
    
    # Add index back
    add_index :special_reservation_dates, :priority
  end
end
