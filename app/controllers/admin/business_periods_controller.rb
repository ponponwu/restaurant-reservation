class Admin::BusinessPeriodsController < AdminController
  before_action :set_restaurant
  before_action :check_restaurant_access
  before_action :set_business_period, only: %i[show edit update destroy toggle_active]

  def index
    @business_periods = @restaurant.business_periods.includes(:reservation_slots).ordered
    @new_business_period = @restaurant.business_periods.build

    respond_to do |format|
      format.html do
        # 如果是 AJAX 請求，不使用 layout
        render layout: false if request.xhr?
      end
      format.turbo_stream
    end
  end

  def show; end

  def new
    @business_period = @restaurant.business_periods.build
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
    @restaurant = if current_user.super_admin?
                    Restaurant.find_by!(slug: params[:restaurant_id])
                  else
                    # 餐廳管理員和員工只能存取自己的餐廳
                    Restaurant.where(id: current_user.restaurant_id).find_by!(slug: params[:restaurant_id])
                  end
  end

  def check_restaurant_access
    return if current_user.can_manage_restaurant?(@restaurant)

    redirect_to admin_restaurants_path, alert: '您沒有權限存取此餐廳的營業時段管理'
  end

  def set_business_period
    @business_period = @restaurant.business_periods.find(params[:id])
  end

  def business_period_params
    permitted_params = params.require(:business_period).permit(
      :name, :display_name, :start_time, :end_time, :status,
      days_of_week: []
    )

    # 確保時間參數使用正確的時區
    if permitted_params[:start_time].present?
      permitted_params[:start_time] = parse_time_in_timezone(permitted_params[:start_time])
    end

    if permitted_params[:end_time].present?
      permitted_params[:end_time] = parse_time_in_timezone(permitted_params[:end_time])
    end

    permitted_params
  end

  def parse_time_in_timezone(time_string)
    # 如果是 HH:MM 格式，添加日期部分並使用正確時區解析
    if time_string.match?(/^\d{2}:\d{2}$/)
      Time.zone.parse("2000-01-01 #{time_string}")
    else
      # 如果已經包含日期，直接解析
      Time.zone.parse(time_string)
    end
  rescue ArgumentError
    # 如果解析失敗，回傳原始值讓 Rails 處理驗證錯誤
    time_string
  end
end
