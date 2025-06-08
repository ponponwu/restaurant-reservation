class CreateReservations < ActiveRecord::Migration[7.1]
  def change
    create_table :reservations do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.references :table, null: false, foreign_key: true
      t.references :business_period, null: false, foreign_key: true
      t.string :customer_name
      t.string :customer_phone
      t.string :customer_email
      t.integer :party_size
      t.datetime :reservation_datetime
      t.text :special_requests
      t.string :status
      t.text :notes

      t.timestamps
    end
  end
end
