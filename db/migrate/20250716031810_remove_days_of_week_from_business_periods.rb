class RemoveDaysOfWeekFromBusinessPeriods < ActiveRecord::Migration[8.0]
  def change
    remove_column :business_periods, :days_of_week, :json
  end
end
