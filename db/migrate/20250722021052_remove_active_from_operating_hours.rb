class RemoveActiveFromOperatingHours < ActiveRecord::Migration[8.0]
  def change
    remove_column :operating_hours, :active, :boolean
  end
end
