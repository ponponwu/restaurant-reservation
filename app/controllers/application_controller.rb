class ApplicationController < ActionController::Base
  # 防止 CSRF 攻擊
  protect_from_forgery with: :exception
  
  # 移除強制登入要求，讓系統可以不登入使用
  # before_action :authenticate_user!, except: [:index, :show, :new, :create]
  before_action :configure_permitted_parameters, if: :devise_controller?
  
  # 設定當前餐廳（如果需要）
  before_action :set_current_restaurant
  
  # 錯誤處理
  rescue_from CanCan::AccessDenied do |exception|
    respond_to do |format|
      format.html { redirect_to root_path, alert: '您沒有權限執行此操作' }
      format.json { render json: { error: '權限不足' }, status: :forbidden }
    end
  end
  
  rescue_from ActiveRecord::RecordNotFound do |exception|
    respond_to do |format|
      format.html { redirect_to root_path, alert: '找不到指定的資源' }
      format.json { render json: { error: '資源不存在' }, status: :not_found }
    end
  end
  
  protected
  
  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name, :role])
    devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name, :role])
  end
  
  def set_current_restaurant
    # 這裡可以根據使用者角色或其他邏輯設定當前餐廳
    # 暫時使用第一個餐廳作為預設
    @current_restaurant = Restaurant.active.first
  end
  
  def current_restaurant
    @current_restaurant
  end
  helper_method :current_restaurant
  
  def ensure_admin_access
    # 暫時移除權限檢查，讓系統可以不登入使用
    # unless current_user&.can_access_admin?
    #   redirect_to root_path, alert: '您沒有權限存取管理後台'
    # end
  end
  
  def ensure_manager_access
    # 暫時移除權限檢查，讓系統可以不登入使用
    # unless current_user&.can_manage_restaurant?
    #   redirect_to admin_root_path, alert: '您沒有權限執行此操作'
    # end
  end
end
