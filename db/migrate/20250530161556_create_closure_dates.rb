class CreateClosureDates < ActiveRecord::Migration[7.1]
  def change
    create_table :closure_dates do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.date :date, null: false
      t.string :reason
      t.integer :closure_type, default: 0
      t.boolean :all_day, default: true
      t.time :start_time
      t.time :end_time
      t.boolean :recurring, default: false
      t.json :recurring_pattern

      t.timestamps
    end
    
    add_index :closure_dates, [:restaurant_id, :date]
    add_index :closure_dates, :date
    add_index :closure_dates, :closure_type
  end
end
