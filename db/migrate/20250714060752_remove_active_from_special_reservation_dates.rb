class RemoveActiveFromSpecialReservationDates < ActiveRecord::Migration[8.0]
  def change
    remove_column :special_reservation_dates, :active, :boolean
  end
end
