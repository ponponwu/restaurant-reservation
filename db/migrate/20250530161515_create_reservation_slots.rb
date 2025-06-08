class CreateReservationSlots < ActiveRecord::Migration[7.1]
  def change
    create_table :reservation_slots do |t|
      t.references :business_period, null: false, foreign_key: true
      t.time :slot_time, null: false
      t.integer :max_capacity, default: 0
      t.integer :interval_minutes, default: 30
      t.integer :reservation_deadline, default: 60
      t.boolean :active, default: true

      t.timestamps
    end
    
    add_index :reservation_slots, [:business_period_id, :slot_time], unique: true
    add_index :reservation_slots, :slot_time
  end
end
