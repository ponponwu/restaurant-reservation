class ChangeTableIdToNullableInReservations < ActiveRecord::Migration[7.1]
  def change
    change_column_null :reservations, :table_id, true
  end
end
