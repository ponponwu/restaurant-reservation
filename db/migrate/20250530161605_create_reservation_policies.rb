class CreateReservationPolicies < ActiveRecord::Migration[7.1]
  def change
    create_table :reservation_policies do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.integer :advance_booking_days, default: 30
      t.integer :minimum_advance_hours, default: 2
      t.integer :max_party_size, default: 10
      t.integer :min_party_size, default: 1
      t.text :no_show_policy
      t.text :modification_policy
      t.boolean :deposit_required, default: false
      t.decimal :deposit_amount, precision: 10, scale: 2, default: 0.0
      t.boolean :deposit_per_person, default: false
      t.json :special_rules

      t.timestamps
    end
  end
end
