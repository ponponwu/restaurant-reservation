class ChangeUserRoleToInteger < ActiveRecord::Migration[7.1]
  def up
    # 添加新的 integer role 欄位
    add_column :users, :role_integer, :integer, default: 2, null: false
    add_index :users, :role_integer
    
    # 轉換現有資料
    User.reset_column_information
    User.find_each do |user|
      case user.role
      when 'super_admin'
        user.update_column(:role_integer, 0)
      when 'admin', 'manager'  # 將現有的 admin 角色轉為 manager
        user.update_column(:role_integer, 1)
      else
        user.update_column(:role_integer, 2)  # employee
      end
    end
    
    # 移除舊的 string role 欄位
    remove_column :users, :role
    
    # 重新命名新欄位
    rename_column :users, :role_integer, :role
  end

  def down
    # 添加舊的 string role 欄位
    add_column :users, :role_string, :string
    
    # 轉換資料回去
    User.reset_column_information
    User.find_each do |user|
      case user.role
      when 0
        user.update_column(:role_string, 'super_admin')
      when 1
        user.update_column(:role_string, 'manager')
      when 2
        user.update_column(:role_string, 'employee')
      end
    end
    
    # 移除 integer role 欄位
    remove_column :users, :role
    
    # 重新命名回原來的欄位
    rename_column :users, :role_string, :role
    remove_index :users, :role if index_exists?(:users, :role)
  end
end
