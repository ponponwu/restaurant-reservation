class AddActiveToTables < ActiveRecord::Migration[7.1]
  def change
    add_column :tables, :active, :boolean, default: true, null: false
  end
end
