class Admin::RestaurantsController < AdminController
  before_action :set_restaurant, only: [:show, :edit, :update, :destroy, :toggle_status]

  def index
    @restaurants = Restaurant.active.includes(:users)
    
    # 簡單搜尋功能
    if params[:search].present?
      @restaurants = @restaurants.search_by_name(params[:search])
    end
    
    @restaurants = @restaurants.page(params[:page]).per(10)

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

  def create
    @restaurant = Restaurant.new(restaurant_params)

    if @restaurant.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.prepend('restaurants_list', partial: 'restaurant_row', locals: { restaurant: @restaurant }),
            turbo_stream.update('restaurant_form', partial: 'form', locals: { restaurant: Restaurant.new }),
            turbo_stream.update('flash_messages', partial: 'shared/flash', locals: { message: '餐廳建立成功', type: 'success' })
          ]
        end
        format.html { redirect_to admin_restaurants_path, notice: '餐廳建立成功' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('restaurant_form', partial: 'form', locals: { restaurant: @restaurant })
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def edit
    respond_to do |format|
      format.html do
        # 如果是 AJAX 請求，不使用 layout
        if request.xhr?
          render layout: false
        end
      end
      format.turbo_stream
    end
  end

  def update
    if @restaurant.update(restaurant_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("restaurant_#{@restaurant.id}", partial: 'restaurant_row', locals: { restaurant: @restaurant }),
            turbo_stream.update('flash_messages', partial: 'shared/flash', locals: { message: '餐廳資料已更新', type: 'success' })
          ]
        end
        format.html { redirect_to admin_restaurants_path, notice: '餐廳資料已更新' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('restaurant_form', partial: 'form', locals: { restaurant: @restaurant })
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
    @restaurant.update!(active: !@restaurant.active?)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("restaurant_#{@restaurant.id}", partial: 'restaurant_row', locals: { restaurant: @restaurant })
      end
    end
  end

  private

  def set_restaurant
    @restaurant = Restaurant.find_by!(slug: params[:id])
  end

  def restaurant_params
    params.require(:restaurant).permit(:name, :description, :phone, :address)
  end
end 