class AddAdvancedFieldsToBusinessPeriods < ActiveRecord::Migration[7.1]
  def change
    add_column :business_periods, :display_name, :string
    add_column :business_periods, :reservation_settings, :json
    add_column :business_periods, :status, :integer
  end
end
