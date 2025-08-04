class CreateSmsLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :sms_logs do |t|
      t.references :reservation, null: false, foreign_key: true
      t.string :phone_number
      t.string :message_type
      t.text :content
      t.string :status
      t.text :response_data

      t.timestamps
    end
  end
end
