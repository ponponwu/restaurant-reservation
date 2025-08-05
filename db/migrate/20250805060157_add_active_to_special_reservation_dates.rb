class AddActiveToSpecialReservationDates < ActiveRecord::Migration[8.0]
  def change
    add_column :special_reservation_dates, :active, :boolean, default: true, null: false
  end
end
