class Admin::RestaurantsController < AdminController
  before_action :set_restaurant, only: %i[show edit update destroy toggle_status]
  before_action :check_restaurant_access, only: %i[show edit update]

  def index
    # 根據用戶角色顯示不同的餐廳列表
    @restaurants = if current_user.super_admin?
                     Restaurant.active.includes(:users)
                   else
                     # 餐廳管理員和員工只能看到自己的餐廳
                     Restaurant.where(id: current_user.restaurant_id).active.includes(:users)
                   end

    # 簡單搜尋功能
    @restaurants = @restaurants.search_by_name(params[:search]) if params[:search].present?

    @pagy, @restaurants = pagy(@restaurants, items: 10)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show
    @users = @restaurant.users.active.limit(5)
    @stats = {
      total_tables: @restaurant.total_tables_count,
      total_capacity: @restaurant.total_capacity,
      available_tables: @restaurant.available_tables_count,
      business_periods: @restaurant.business_periods.count
    }
  end

  def new
    @restaurant = Restaurant.new
  end

  def edit
    respond_to do |format|
      format.html do
        # 如果是 AJAX 請求，不使用 layout
        render layout: false if request.xhr?
      end
      format.turbo_stream
    end
  end

  def create
    @restaurant = Restaurant.new(restaurant_params)

    if @restaurant.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.prepend('restaurants_list', partial: 'restaurant_row', locals: { restaurant: @restaurant }),
            turbo_stream.update('restaurant_form', partial: 'form', locals: { restaurant: Restaurant.new }),
            turbo_stream.update('flash_messages', partial: 'shared/flash',
                                                  locals: { message: '餐廳建立成功', type: 'success' })
          ]
        end
        format.html { redirect_to admin_restaurants_path, notice: '餐廳建立成功' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('restaurant_form', partial: 'form',
                                                                      locals: { restaurant: @restaurant })
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def update
    if @restaurant.update(restaurant_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("restaurant_#{@restaurant.id}", partial: 'restaurant_row',
                                                                 locals: { restaurant: @restaurant }),
            turbo_stream.update('flash_messages', partial: 'shared/flash',
                                                  locals: { message: '餐廳資料已更新', type: 'success' })
          ]
        end
        format.html { redirect_to admin_restaurant_path(@restaurant), notice: '餐廳資料已更新' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('restaurant_form', partial: 'form',
                                                                      locals: { restaurant: @restaurant })
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @restaurant.soft_delete!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("restaurant_#{@restaurant.id}"),
          turbo_stream.update('flash_messages', partial: 'shared/flash', locals: { message: '餐廳已刪除', type: 'success' })
        ]
      end
      format.html { redirect_to admin_restaurants_path, notice: '餐廳已刪除' }
    end
  end

  def toggle_status
    # 檢查權限
    unless current_user.super_admin?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('flash_messages',
                                                   partial: 'shared/flash',
                                                   locals: { message: '您沒有權限修改餐廳狀態', type: 'error' })
        end
        format.html { redirect_to admin_restaurants_path, alert: '您沒有權限修改餐廳狀態' }
        format.json { render json: { success: false, message: '權限不足' } }
      end
      return
    end

    @restaurant.update!(active: !@restaurant.active?)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("restaurant_#{@restaurant.id}",
                               partial: 'restaurant_row',
                               locals: { restaurant: @restaurant }),
          turbo_stream.update('flash_messages',
                              partial: 'shared/flash',
                              locals: {
                                message: "餐廳已#{@restaurant.active? ? '啟用' : '停用'}",
                                type: 'success'
                              })
        ]
      end
      format.html { redirect_to admin_restaurants_path, notice: "餐廳已#{@restaurant.active? ? '啟用' : '停用'}" }
      format.json { render json: { success: true, active: @restaurant.active? } }
    end
  end

  private

  def set_restaurant
    @restaurant = if current_user.super_admin?
                    Restaurant.find_by!(slug: params[:id])
                  else
                    # 餐廳管理員和員工只能存取自己的餐廳
                    Restaurant.where(id: current_user.restaurant_id).find_by!(slug: params[:id])
                  end
  end

  def check_restaurant_access
    return if current_user.can_manage_restaurant?(@restaurant)

    redirect_to admin_restaurants_path, alert: '您沒有權限存取此餐廳'
  end

  def restaurant_params
    params.require(:restaurant).permit(:name, :description, :phone, :address, :business_name, :tax_id, :reminder_notes,
                                       :hero_image)
  end
end
