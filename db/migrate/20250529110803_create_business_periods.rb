class CreateBusinessPeriods < ActiveRecord::Migration[7.1]
  def change
    create_table :business_periods do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.string :name
      t.time :start_time
      t.time :end_time
      t.json :days_of_week
      t.boolean :active

      t.timestamps
    end
  end
end
