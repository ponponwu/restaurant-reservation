class CreateOperatingHours < ActiveRecord::Migration[8.0]
  def change
    create_table :operating_hours do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.integer :weekday, null: false, comment: "星期幾 (0=日, 1=一, ..., 6=六)"
      t.time :open_time, null: false
      t.time :close_time, null: false
      t.boolean :active, default: true

      t.timestamps
    end
    
    add_index :operating_hours, [:restaurant_id, :weekday], unique: true
    add_index :operating_hours, :weekday
  end
end
