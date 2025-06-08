class Admin::BusinessPeriodsController < AdminController
  before_action :set_restaurant
  before_action :set_business_period, only: [:show, :edit, :update, :destroy, :toggle_active]

  def index
    @business_periods = @restaurant.business_periods.includes(:reservation_slots).ordered
    @new_business_period = @restaurant.business_periods.build
    
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

  def show
  end

  def new
    @business_period = @restaurant.business_periods.build
  end

  def create
    @business_period = @restaurant.business_periods.build(business_period_params)

    if @business_period.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append('business_periods_list', 
                               partial: 'business_period_row', 
                               locals: { business_period: @business_period }),
            turbo_stream.update('flash_messages', 
                               partial: 'shared/flash', 
                               locals: { message: '營業時段建立成功', type: 'success' }),
            turbo_stream.update('new_business_period_form', 
                               partial: 'form', 
                               locals: { business_period: @restaurant.business_periods.build })
          ]
        end
        format.html { redirect_to admin_restaurant_business_periods_path(@restaurant), notice: '營業時段建立成功' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('new_business_period_form', 
                                                  partial: 'form', 
                                                  locals: { business_period: @business_period })
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
    if @business_period.update(business_period_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("business_period_#{@business_period.id}", 
                                partial: 'business_period_row', 
                                locals: { business_period: @business_period }),
            turbo_stream.update('flash_messages', 
                               partial: 'shared/flash', 
                               locals: { message: '營業時段更新成功', type: 'success' }),
            turbo_stream.update('modal', '')
          ]
        end
        format.html { redirect_to admin_restaurant_business_periods_path(@restaurant), notice: '營業時段更新成功' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('modal', 
                                                  partial: 'edit', 
                                                  locals: { business_period: @business_period })
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @business_period.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("business_period_#{@business_period.id}"),
          turbo_stream.update('flash_messages', 
                             partial: 'shared/flash', 
                             locals: { message: '營業時段已刪除', type: 'success' })
        ]
      end
      format.html { redirect_to admin_restaurant_business_periods_path(@restaurant), notice: '營業時段已刪除' }
    end
  end

  def toggle_active
    @business_period.update!(status: @business_period.active? ? :inactive : :active)
    
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("business_period_#{@business_period.id}", 
                              partial: 'business_period_row', 
                              locals: { business_period: @business_period }),
          turbo_stream.update('flash_messages', 
                             partial: 'shared/flash', 
                             locals: { message: "營業時段已#{@business_period.active? ? '啟用' : '停用'}", type: 'success' })
        ]
      end
      format.html { redirect_to admin_restaurant_business_periods_path(@restaurant) }
    end
  end

  private

  def set_restaurant
    @restaurant = Restaurant.find_by!(slug: params[:restaurant_id])
    
    # super_admin 和 manager 可以管理所有餐廳
    unless current_user.super_admin? || current_user.manager?
      redirect_to admin_restaurants_path, alert: '您沒有權限管理此餐廳'
    end
  end

  def set_business_period
    @business_period = @restaurant.business_periods.find(params[:id])
  end

  def business_period_params
    params.require(:business_period).permit(
      :name, :display_name, :start_time, :end_time, :status,
      days_of_week: []
    )
  end
end
