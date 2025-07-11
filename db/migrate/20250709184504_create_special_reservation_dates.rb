class CreateSpecialReservationDates < ActiveRecord::Migration[7.1]
  def change
    create_table :special_reservation_dates do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.string :name, null: false, limit: 100
      t.text :description, limit: 500
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :operation_mode, null: false, default: 'closed'
      t.integer :table_usage_minutes
      t.json :custom_periods, default: []
      t.boolean :active, default: true, null: false
      t.integer :priority, default: 0, null: false

      t.timestamps
    end

    add_index :special_reservation_dates, [:start_date, :end_date]
    add_index :special_reservation_dates, :active
    add_index :special_reservation_dates, :priority
  end
end
