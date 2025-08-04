class Admin::OperatingHoursController < AdminController
  before_action :set_restaurant
  before_action :check_restaurant_access
  before_action :set_operating_hour, only: %i[show edit update destroy]

  def index
    @operating_hours = @restaurant.operating_hours.ordered
    @new_operating_hour = @restaurant.operating_hours.build

    respond_to do |format|
      format.html do
        render layout: false if request.xhr?
      end
      format.turbo_stream
    end
  end

  def show
    respond_to do |format|
      format.html { render layout: false if request.xhr? }
      format.turbo_stream
    end
  end

  def new
    @operating_hour = @restaurant.operating_hours.build

    if params[:weekday].present?
      @operating_hour.weekday = params[:weekday].to_i
      @preset_weekday = params[:weekday].to_i
    end

    respond_to do |format|
      format.html { render layout: false if request.xhr? }
      format.turbo_stream
    end
  end

  def edit
    respond_to do |format|
      format.html { render layout: false if request.xhr? }
      format.turbo_stream
    end
  end

  def create
    @operating_hour = @restaurant.operating_hours.build(operating_hour_params)

    respond_to do |format|
      if @operating_hour.save
        format.html { redirect_to admin_restaurant_operating_hours_path(@restaurant), notice: '營業時間建立成功' }
        format.turbo_stream # 使用 create.turbo_stream.erb
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('modal',
                                                   partial: 'admin/operating_hours/form_modal',
                                                   locals: { operating_hour: @operating_hour, restaurant: @restaurant })
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      if @operating_hour.update(operating_hour_params)
        format.turbo_stream # 使用 update.turbo_stream.erb
        format.html { redirect_to admin_restaurant_operating_hours_path(@restaurant), notice: '營業時間更新成功' }
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('modal',
                                                   partial: 'admin/operating_hours/form_modal',
                                                   locals: { operating_hour: @operating_hour, restaurant: @restaurant })
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    # 保存 weekday 用於 turbo_stream 模板
    @weekday = @operating_hour.weekday
    @operating_hour.destroy

    respond_to do |format|
      format.turbo_stream # 使用 destroy.turbo_stream.erb
      format.html { redirect_to admin_restaurant_operating_hours_path(@restaurant), notice: '營業時間刪除成功' }
    end
  end

  private

  def set_restaurant
    @restaurant = if current_user.super_admin?
                    Restaurant.find_by!(slug: params[:restaurant_id] || params[:slug])
                  else
                    current_user.restaurant
                  end
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_root_path, alert: '找不到指定的餐廳'
  end

  def set_operating_hour
    @operating_hour = @restaurant.operating_hours.find(params[:id])
  end

  def operating_hour_params
    permitted_params = params.expect(operating_hour: %i[weekday open_time close_time])

    # 確保時間參數使用正確的時區
    if permitted_params[:open_time].present?
      permitted_params[:open_time] = parse_time_in_timezone(permitted_params[:open_time])
    end

    if permitted_params[:close_time].present?
      permitted_params[:close_time] = parse_time_in_timezone(permitted_params[:close_time])
    end

    permitted_params
  end

  def parse_time_in_timezone(time_string)
    # 處理 HH:MM 格式的時間字串
    if time_string.is_a?(String) && time_string.match?(/\A\d{2}:\d{2}\z/)
      Time.zone.parse("#{Date.current} #{time_string}")
    else
      time_string
    end
  end
end
