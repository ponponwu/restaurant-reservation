class AddFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :active, :boolean, default: true
    add_column :users, :deleted_at, :datetime
    add_reference :users, :restaurant, null: true, foreign_key: true
    
    add_index :users, :active
    add_index :users, :deleted_at
  end
end
