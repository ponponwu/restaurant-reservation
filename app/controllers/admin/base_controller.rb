class Admin::BaseController < ApplicationController
  # 確保只有管理員可以存取
  before_action :ensure_admin_access
  
  # 設定佈局
  layout 'admin'
  
  protected
  
  def set_restaurant
    @restaurant = Restaurant.find_by!(slug: params[:restaurant_id]) if params[:restaurant_id]
    @restaurant ||= current_restaurant
    
    # 檢查權限：super_admin 和 manager 可以管理所有餐廳
    if @restaurant && current_user && !current_user.super_admin? && !current_user.manager?
      redirect_to admin_restaurants_path, alert: '您沒有權限管理此餐廳'
    end
  end
  
  def restaurant_required
    unless @restaurant
      redirect_to admin_restaurants_path, alert: '請先選擇餐廳'
    end
  end
end 