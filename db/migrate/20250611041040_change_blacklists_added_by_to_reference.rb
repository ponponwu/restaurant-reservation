class ChangeBlacklistsAddedByToReference < ActiveRecord::Migration[7.1]
  def up
    # 移除原有的 added_by_name 欄位（如果存在）
    if column_exists?(:blacklists, :added_by_name)
      remove_column :blacklists, :added_by_name
    end
    
    # 新增 added_by_id 欄位（如果不存在）
    unless column_exists?(:blacklists, :added_by_id)
      add_reference :blacklists, :added_by, null: false, foreign_key: { to_table: :users }, default: 1
      add_index :blacklists, :added_by_id unless index_exists?(:blacklists, :added_by_id)
    end
  end

  def down
    # 回滾時移除 added_by_id 並恢復 added_by_name
    if column_exists?(:blacklists, :added_by_id)
      remove_foreign_key :blacklists, :users if foreign_key_exists?(:blacklists, :users, column: :added_by_id)
      remove_index :blacklists, :added_by_id if index_exists?(:blacklists, :added_by_id)
      remove_reference :blacklists, :added_by
    end
    
    unless column_exists?(:blacklists, :added_by_name)
      add_column :blacklists, :added_by_name, :string
    end
  end
end
