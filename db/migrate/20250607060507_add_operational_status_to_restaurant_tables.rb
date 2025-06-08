class AddOperationalStatusToRestaurantTables < ActiveRecord::Migration[7.1]
  def change
    add_column :restaurant_tables, :operational_status, :string, default: 'normal', null: false
    add_index :restaurant_tables, :operational_status
    
    # 遷移現有資料
    reversible do |dir|
      dir.up do
        # 將現有的 status 對應到新的 operational_status
        execute <<-SQL
          UPDATE restaurant_tables 
          SET operational_status = CASE 
            WHEN status IN ('available', 'occupied', 'reserved') THEN 'normal'
            WHEN status = 'maintenance' THEN 'maintenance'
            WHEN status = 'cleaning' THEN 'cleaning'
            ELSE 'normal'
          END
        SQL
      end
      
      dir.down do
        # 回滾時恢復 status
        execute <<-SQL
          UPDATE restaurant_tables 
          SET status = CASE 
            WHEN operational_status = 'normal' THEN 'available'
            WHEN operational_status = 'maintenance' THEN 'maintenance'
            WHEN operational_status = 'cleaning' THEN 'cleaning'
            WHEN operational_status = 'out_of_service' THEN 'maintenance'
            ELSE 'available'
          END
        SQL
      end
    end
  end
end
