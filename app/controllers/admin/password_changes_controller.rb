class Admin::PasswordChangesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_needs_password_change

  def show
    # 顯示密碼修改表單
  end

  def update
    if current_user.update(password_params)
      current_user.mark_password_changed!
      
      # 根據角色重定向到不同頁面
      if current_user.super_admin?
        redirect_to admin_root_path, notice: '密碼修改成功！歡迎使用系統管理後台。'
      elsif current_user.manager? && current_user.restaurant
        redirect_to admin_restaurant_reservations_path(current_user.restaurant), notice: '密碼修改成功！歡迎使用餐廳管理系統。'
      else
        redirect_to admin_root_path, notice: '密碼修改成功！'
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def ensure_needs_password_change
    unless current_user.needs_password_change?
      # 如果不需要修改密碼，根據角色重定向
      if current_user.super_admin?
        redirect_to admin_root_path and return
      elsif current_user.manager?
        redirect_to admin_restaurant_reservations_path(current_user.restaurant) and return
      else
        redirect_to admin_root_path and return
      end
    end
  end

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end 