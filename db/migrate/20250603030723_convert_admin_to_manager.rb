class ConvertAdminToManager < ActiveRecord::Migration[7.1]
  def up
    # 檢查是否有現存的用戶需要角色轉換
    User.reset_column_information
    
    User.find_each do |user|
      # 如果角色值不在有效範圍內，設為 manager (1)
      unless user.role.in?([0, 1, 2])  # super_admin, manager, employee
        Rails.logger.info "轉換用戶 #{user.email} 的角色從 #{user.role} 到 manager"
        user.update_column(:role, 1)  # manager
      end
    end
    
    # 確保至少有一個 super_admin 用戶
    unless User.where(role: 0).exists?  # super_admin = 0
      # 建立預設的 super_admin
      User.create!(
        email: 'super_admin@system.com',
        password: 'password123',
        password_confirmation: 'password123',
        first_name: '系統',
        last_name: '管理員',
        role: 0,  # super_admin
        active: true
      )
      Rails.logger.info "建立預設系統管理員: super_admin@system.com"
    end
  end

  def down
    # 不需要回滾操作，因為這是資料修正
  end
end
