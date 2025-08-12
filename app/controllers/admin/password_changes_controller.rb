class Admin::PasswordChangesController < ApplicationController
  before_action :authenticate_user!

  def show
    # 根據使用者狀態決定渲染哪個視圖
    if current_user.needs_password_change?
      # 強制修改密碼：使用 show 視圖（全屏模式）
      render :show
    else
      # 自主修改密碼：使用 edit 視圖（管理員布局）
      render :edit
    end
  end

  def update
    if current_user.update(password_params)
      current_user.mark_password_changed!
      bypass_sign_in(current_user) # 重新登入使用者

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


  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
