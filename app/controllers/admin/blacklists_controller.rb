class Admin::BlacklistsController < Admin::BaseController
  before_action :set_restaurant
  before_action :check_restaurant_access
  before_action :set_blacklist, only: %i[show edit update destroy toggle_active]

  def index
    @q = @restaurant.blacklists.ransack(params[:q])
    @pagy, @blacklists = pagy(@q.result.recent, items: 20)

    respond_to do |format|
      format.html
    end
  end

  def show; end

  def new
    @blacklist = @restaurant.blacklists.build

    # 如果從訂位頁面跳轉過來，預填客戶資訊
    if params[:customer_phone].present?
      @blacklist.customer_phone = params[:customer_phone]
      @blacklist.customer_name = params[:customer_name]
    end

    respond_to do |format|
      format.html do
        # 如果是 AJAX 請求，不使用佈局
        render layout: false if request.xhr? || request.headers['X-Requested-With'] == 'XMLHttpRequest'
      end
      format.json { render json: @blacklist }
    end
  end

  def edit; end

  def create
    @blacklist = @restaurant.blacklists.new(blacklist_params)
    @blacklist.added_by = current_user

    respond_to do |format|
      if @blacklist.save
        format.html { redirect_to admin_restaurant_blacklists_path(@restaurant), notice: '黑名單已成功建立' }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.update('modal-content',
                                partial: 'admin/blacklists/success',
                                locals: { message: '黑名單已成功建立' }),
            turbo_stream.after('body',
                               partial: 'shared/flash',
                               locals: { message: '黑名單已成功建立', type: 'success' })
          ]
        end
      else
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('modal-content',
                                                   partial: 'admin/blacklists/form',
                                                   locals: { blacklist: @blacklist }),
                 status: :unprocessable_entity
        end
      end
    end
  end

  def update
    if @blacklist.update(blacklist_params)
      redirect_to admin_restaurant_blacklists_path(@restaurant), notice: '黑名單已更新'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    customer_name = @blacklist.customer_name
    @blacklist.destroy

    # 強制使用 HTML 格式重導向
    redirect_to admin_restaurant_blacklists_path(@restaurant), notice: "已成功刪除黑名單：#{customer_name}"
  end

  def toggle_active
    if @blacklist.active?
      @blacklist.deactivate!
      message = '已停用黑名單'
    else
      @blacklist.activate!
      message = '已啟用黑名單'
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("blacklist_#{@blacklist.id}",
                               partial: 'blacklist',
                               locals: { blacklist: @blacklist }),
          turbo_stream.update('flash',
                              partial: 'shared/flash',
                              locals: { message: message, type: 'success' })
        ]
      end
      format.html { redirect_to admin_restaurant_blacklists_path(@restaurant), notice: message }
    end
  end

  private

  def set_restaurant
    if current_user.super_admin?
      # 從路由參數中獲取餐廳
      @restaurant = Restaurant.find_by!(slug: params[:restaurant_id])
    else
      # 餐廳管理員和員工只能存取自己的餐廳
      @restaurant = current_user.restaurant

      # 檢查路由參數中的餐廳是否與用戶的餐廳一致
      if params[:restaurant_id].present?
        requested_restaurant = Restaurant.find_by!(slug: params[:restaurant_id])
        unless @restaurant == requested_restaurant
          redirect_to admin_restaurants_path, alert: '您沒有權限存取此餐廳'
          return
        end
      end
    end

    # 如果還是沒有餐廳，拋出錯誤
    return if @restaurant

    redirect_to admin_restaurants_path, alert: '找不到指定的餐廳'
  end

  def check_restaurant_access
    return if current_user.can_manage_restaurant?(@restaurant)

    redirect_to admin_restaurants_path, alert: '您沒有權限存取此餐廳的黑名單管理'
  end

  def set_blacklist
    @blacklist = @restaurant.blacklists.find(params[:id])
  end

  def blacklist_params
    params.require(:blacklist).permit(
      :customer_name, :customer_phone, :reason, :active
    )
  end

  def render_turbo_stream_update(success: true)
    respond_to do |format|
      format.turbo_stream do
        Rails.logger.info '🌊 正在渲染 turbo_stream 回應'
      end
      format.html { redirect_to admin_blacklists_path, notice: '黑名單新增成功' }
    end
  end
end
