class Admin::RestaurantSettings::SpecialDatesController < AdminController
  before_action :set_restaurant
  before_action :check_restaurant_access
  before_action :set_special_date, only: %i[edit update destroy]

  def index
    @special_dates = @restaurant.special_reservation_dates
      .includes(:restaurant)
      .order(:start_date, :created_at)

    @closure_dates = @restaurant.closure_dates.order(:date, :created_at)

    # 分別處理不同類型的特殊日期
    @closed_dates = @special_dates.closed
    @custom_dates = @special_dates.custom_hours

    respond_to do |format|
      format.html do
        render layout: false if request.xhr?
      end
      format.turbo_stream
    end
  end

  def new
    @special_date = @restaurant.special_reservation_dates.build
    @special_date.operation_mode = params[:mode] || 'closed'

    # 設定預設值
    if @special_date.custom_hours?
      @special_date.table_usage_minutes = 120
      @special_date.custom_periods = [
        {
          start_time: '18:00',
          end_time: '21:00',
          interval_minutes: 120
        }
      ]
    end

    render layout: false if request.xhr?
  end

  def edit
    respond_to do |format|
      format.html do
        render layout: false if request.xhr?
      end
      format.turbo_stream
    end
  end

  def create
    @special_date = @restaurant.special_reservation_dates.build(special_date_params)

    if @special_date.save
      respond_to do |format|
        format.turbo_stream do
          @special_dates = @restaurant.special_reservation_dates
            .order(:start_date, :created_at)

          render turbo_stream: [
            turbo_stream.replace('special_dates_content',
                                 partial: 'special_dates_content',
                                 locals: { restaurant: @restaurant, special_dates: @special_dates }),
            turbo_stream.update('flash_messages',
                                partial: 'shared/flash',
                                locals: { message: '特殊日期設定成功', type: 'success' }),
            turbo_stream.append_all('body', "<script>document.dispatchEvent(new CustomEvent('close-modal'))</script>")
          ]
        end
        format.html do
          redirect_to admin_restaurant_settings_restaurant_special_dates_path(@restaurant),
                      notice: '特殊日期設定成功'
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(dom_id(@special_date, :form_modal),
                                                   partial: 'form_modal',
                                                   locals: { special_date: @special_date })
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def update
    if @special_date.update(special_date_params)
      respond_to do |format|
        format.turbo_stream do
          @special_dates = @restaurant.special_reservation_dates
            .order(:start_date, :created_at)

          render turbo_stream: [
            turbo_stream.replace('special_dates_content',
                                 partial: 'special_dates_content',
                                 locals: { restaurant: @restaurant, special_dates: @special_dates }),
            turbo_stream.update('flash_messages',
                                partial: 'shared/flash',
                                locals: { message: '特殊日期更新成功', type: 'success' }),
            turbo_stream.append_all('body', "<script>document.dispatchEvent(new CustomEvent('close-modal'))</script>")
          ]
        end
        format.html do
          redirect_to admin_restaurant_settings_restaurant_special_dates_path(@restaurant),
                      notice: '特殊日期更新成功'
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(dom_id(@special_date, :form_modal),
                                                   partial: 'form_modal',
                                                   locals: { special_date: @special_date })
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @special_date.destroy

    respond_to do |format|
      format.turbo_stream do
        @special_dates = @restaurant.special_reservation_dates
          .order(:start_date, :created_at)

        render turbo_stream: [
          turbo_stream.replace('special_dates_content',
                               partial: 'special_dates_content',
                               locals: { restaurant: @restaurant, special_dates: @special_dates }),
          turbo_stream.update('flash_messages',
                              partial: 'shared/flash',
                              locals: { message: '特殊日期已刪除', type: 'success' })
        ]
      end
      format.html do
        redirect_to admin_restaurant_settings_restaurant_special_dates_path(@restaurant),
                    notice: '特殊日期已刪除'
      end
    end
  end

  # def toggle_active
  #   @special_date.update!(active: !@special_date.active?)

  #   respond_to do |format|
  #     format.turbo_stream do
  #       @special_dates = @restaurant.special_reservation_dates
  #         .order(:start_date, :created_at)

  #       render turbo_stream: [
  #         turbo_stream.replace('special_dates_content',
  #                              partial: 'special_dates_content',
  #                              locals: { restaurant: @restaurant, special_dates: @special_dates }),
  #         turbo_stream.update('flash_messages',
  #                             partial: 'shared/flash',
  #                             locals: {
  #                               message: "特殊日期已#{@special_date.active? ? '啟用' : '停用'}",
  #                               type: 'success'
  #                             })
  #       ]
  #     end
  #     format.html do
  #       redirect_to admin_restaurant_settings_restaurant_special_dates_path(@restaurant)
  #     end
  #   end
  # end

  private

  def set_restaurant
    @restaurant = if current_user.super_admin?
                    Restaurant.find_by!(slug: params[:restaurant_slug])
                  else
                    unless current_user.restaurant_id.present?
                      raise ActiveRecord::RecordNotFound, 'User has no restaurant association'
                    end

                    Restaurant.where(id: current_user.restaurant_id).find_by!(slug: params[:restaurant_slug])
                  end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "Restaurant access denied: #{e.message} for user #{current_user.id}"
    redirect_to admin_restaurants_path, alert: '您沒有權限存取此餐廳的特殊日期設定'
  end

  def set_special_date
    @special_date = @restaurant.special_reservation_dates.find(params[:id])
  end

  def special_date_params
    permitted = params.require(:special_reservation_date).permit(
      :name, :description, :start_date, :end_date, :operation_mode,
      :table_usage_minutes
    )

    # Manually process custom_periods
    custom_periods_params = params.dig(:special_reservation_date, :custom_periods)

    if custom_periods_params.is_a?(ActionController::Parameters)
      processed_periods = []
      custom_periods_params.each_value do |period_param|
        permitted_period = period_param.permit(:start_time, :end_time, :interval_minutes)

        next unless permitted_period[:start_time].present? && permitted_period[:end_time].present?

        processed_periods << {
          start_time: permitted_period[:start_time],
          end_time: permitted_period[:end_time],
          interval_minutes: permitted_period[:interval_minutes].to_i
        }
      end
      permitted[:custom_periods] = processed_periods
    else
      permitted[:custom_periods] = []
    end

    permitted
  end
end
