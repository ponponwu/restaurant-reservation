class DropReservationLocks < ActiveRecord::Migration[8.0]
  def up
    drop_table :reservation_locks
  end

  def down
    create_table :reservation_locks do |t|
      t.string :lock_key
      t.string :lock_value
      t.datetime :expires_at
      t.timestamps
    end
    add_index :reservation_locks, :lock_key, unique: true
    add_index :reservation_locks, :expires_at
  end
end
