class ApplicationController < ActionController::Base
  # 防止 CSRF 攻擊
  protect_from_forgery with: :exception

  # 加入 Pagy helper
  include Pagy::Backend

  # 移除強制登入要求，讓系統可以不登入使用
  # before_action :authenticate_user!, except: [:index, :show, :new, :create]
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :check_password_change_required

  # 設定當前餐廳（如果需要）
  before_action :set_current_restaurant

  # 錯誤處理
  rescue_from CanCan::AccessDenied do |_exception|
    respond_to do |format|
      format.html { redirect_to root_path, alert: '您沒有權限執行此操作' }
      format.json { render json: { error: '權限不足' }, status: :forbidden }
    end
  end

  rescue_from ActiveRecord::RecordNotFound do |_exception|
    respond_to do |format|
      format.html { redirect_to root_path, alert: '找不到指定的資源' }
      format.json { render json: { error: '資源不存在' }, status: :not_found }
    end
  end

  rescue_from StandardError do |exception|
    # 在日誌中記錄詳細錯誤
    logger.error "Unhandled error: #{exception.message}"
    logger.error exception.backtrace.join("\n")

    respond_to do |format|
      format.html { render file: Rails.public_path.join('500.html'), status: :internal_server_error, layout: false }
      format.json { render json: { error: '伺服器內部錯誤' }, status: :internal_server_error }
    end
  end

  protected

  # Devise 登入後跳轉邏輯
  def after_sign_in_path_for(resource)
    # 如果需要修改密碼，跳轉到密碼修改頁面
    if resource.needs_password_change?
      admin_password_change_path
    else
      # 根據角色決定跳轉頁面
      case resource.role
      when 'super_admin'
        admin_root_path
      when 'manager', 'employee'
        if resource.restaurant.present?
          # 跳轉到餐廳首頁
          admin_restaurant_path(resource.restaurant)
        else
          # 如果沒有關聯餐廳，跳轉到餐廳列表讓他們選擇
          admin_restaurants_path
        end
      else
        admin_root_path
      end
    end
  end

  # Devise 登出後跳轉邏輯
  def after_sign_out_path_for(_resource_or_scope)
    root_path
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[first_name last_name role])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[first_name last_name role])
  end

  def set_current_restaurant
    # 這裡可以根據使用者角色或其他邏輯設定當前餐廳
    # 暫時使用第一個餐廳作為預設
    @current_restaurant = Restaurant.active.first
  end

  attr_reader :current_restaurant

  helper_method :current_restaurant

  def ensure_admin_access
    unless current_user&.can_access_admin?
      redirect_to new_user_session_path, alert: '請先登入以存取管理後台'
    end
  end

  def ensure_manager_access
    unless current_user&.can_manage_restaurant?
      redirect_to admin_root_path, alert: '您沒有權限執行此操作'
    end
  end

  def check_password_change_required
    return unless user_signed_in?
    return if devise_controller?
    return if controller_name == 'password_changes'

    return unless current_user.needs_password_change?

    redirect_to admin_password_change_path
  end
end
