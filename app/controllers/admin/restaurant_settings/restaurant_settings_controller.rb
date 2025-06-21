class Admin::RestaurantSettings::RestaurantSettingsController < AdminController
  before_action :set_restaurant
  before_action :set_closure_dates, only: %i[closure_dates create_closure_date]
  before_action :set_reservation_policy, only: %i[index reservation_policies update_reservation_policy]

  def index
    @stats = calculate_stats
  end

  def business_periods
    @business_periods = @restaurant.business_periods.includes(:reservation_slots)
  end

  def closure_dates
    # @closure_dates 已在 before_action 中設定
    respond_to do |format|
      format.html do
        # 如果是 AJAX 請求，不使用 layout
        render layout: false if request.xhr?
      end
      format.turbo_stream
    end
  end

  def create_closure_date
    @closure_date = @restaurant.closure_dates.build(closure_date_params)

    if @closure_date.save
      respond_to do |format|
        format.turbo_stream do
          @closure_dates = @restaurant.closure_dates.order(:date, :created_at)

          if @closure_date.recurring?
            # 重複公休：更新左側每週公休區域，而不是整個頁面
            render turbo_stream: [
              turbo_stream.replace('weekly-closure-section',
                                   partial: 'weekly_closure_section',
                                   locals: { restaurant: @restaurant, closure_dates: @closure_dates }),
              turbo_stream.update('modal_flash_messages',
                                  partial: 'shared/flash_message',
                                  locals: { message: '每週公休設定成功', type: 'success' })
            ]
          else
            # 特別日公休：只新增項目
            render turbo_stream: [
              turbo_stream.prepend('closure_dates_list',
                                   partial: 'closure_date_item',
                                   locals: { closure_date: @closure_date, restaurant: @restaurant }),
              turbo_stream.update('modal_flash_messages',
                                  partial: 'shared/flash_message',
                                  locals: { message: '特別日公休設定成功', type: 'success' })
            ]
          end
        end
        format.html do
          redirect_to admin_restaurant_settings_restaurant_closure_dates_path(@restaurant), notice: '公休日建立成功'
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          # 顯示錯誤訊息，先簡單地記錄到 console
          error_messages = @closure_date.errors.full_messages.join(', ')
          Rails.logger.error "Closure date creation failed: #{error_messages}"
          render turbo_stream: turbo_stream.update('closure-dates-content',
                                                   plain: "建立失敗：#{error_messages}")
        end
        format.html { render :closure_dates, status: :unprocessable_entity }
      end
    end
  end

  def create_weekly_closure
    weekday = params[:weekday].to_i
    reason = params[:reason] || '每週定休'

    # 建立重複性公休日記錄
    @closure_date = @restaurant.closure_dates.build(
      date: Date.current.beginning_of_week + weekday.days,
      reason: reason,
      closure_type: :regular,
      all_day: true,
      recurring: true,
      weekday: weekday
    )

    if @closure_date.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.prepend('closure_dates_list',
                                 partial: 'closure_date_item',
                                 locals: { closure_date: @closure_date }),
            turbo_stream.update('flash',
                                partial: 'shared/flash',
                                locals: { message: '每週定休日設定成功', type: 'success' })
          ]
        end
        format.html do
          redirect_to admin_restaurant_settings_restaurant_closure_dates_path(@restaurant), notice: '每週定休日設定成功'
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('flash',
                                                   partial: 'shared/flash',
                                                   locals: { message: '設定失敗', type: 'error' })
        end
        format.html { redirect_to admin_restaurant_settings_restaurant_closure_dates_path(@restaurant), alert: '設定失敗' }
      end
    end
  end

  def destroy_closure_date
    @closure_date = @restaurant.closure_dates.find(params[:closure_date_id])
    is_recurring = @closure_date.recurring?
    @closure_date.destroy

    respond_to do |format|
      format.turbo_stream do
        @closure_dates = @restaurant.closure_dates.order(:date, :created_at)

        if is_recurring
          # 重複公休：更新左側每週公休區域
          render turbo_stream: [
            turbo_stream.replace('weekly-closure-section',
                                 partial: 'weekly_closure_section',
                                 locals: { restaurant: @restaurant, closure_dates: @closure_dates }),
            turbo_stream.update('modal_flash_messages',
                                partial: 'shared/flash_message',
                                locals: { message: '每週公休已取消', type: 'success' })
          ]
        else
          # 特別日公休：只移除項目
          render turbo_stream: [
            turbo_stream.remove("closure_date_#{@closure_date.id}"),
            turbo_stream.update('modal_flash_messages',
                                partial: 'shared/flash_message',
                                locals: { message: '特別日公休已刪除', type: 'success' })
          ]
        end
      end
      format.html { redirect_to admin_restaurant_settings_restaurant_closure_dates_path(@restaurant), notice: '公休日已刪除' }
    end
  end

  def reservation_policies
    # @reservation_policy 已在 before_action 中設定
  end

  def update_reservation_policy
    if @reservation_policy.update(reservation_policy_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('flash',
                                                   partial: 'shared/flash',
                                                   locals: { message: '預約規則更新成功', type: 'success' })
        end
        format.html do
          redirect_to admin_restaurant_settings_restaurant_reservation_policies_path(@restaurant), notice: '預約規則更新成功'
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('flash',
                                                   partial: 'shared/flash',
                                                   locals: {
                                                     message: @reservation_policy.errors.full_messages.join(', '), type: 'error'
                                                   })
        end
        format.html { render :reservation_policies, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_restaurant
    @restaurant = Restaurant.find_by!(slug: params[:restaurant_slug])

    # super_admin 和 manager 可以管理所有餐廳
    return if current_user.super_admin? || current_user.manager?

    redirect_to admin_restaurants_path, alert: '您沒有權限管理此餐廳'
  end

  def set_closure_dates
    @closure_dates = @restaurant.closure_dates
      .order(:date, :created_at)
  end

  def set_reservation_policy
    @reservation_policy = @restaurant.reservation_policy || @restaurant.build_reservation_policy
  end

  def calculate_stats
    {
      total_periods: @restaurant.business_periods.count,
      active_periods: @restaurant.business_periods.active.count,
      total_slots: @restaurant.business_periods.joins(:reservation_slots).count,
      closure_days: @restaurant.closure_dates
        .where(date: Date.current.all_month)
        .count
    }
  end

  def closure_date_params
    params.require(:closure_date).permit(
      :date, :reason, :closure_type, :all_day, :start_time, :end_time,
      :recurring, :weekday
    )
  end

  def reservation_policy_params
    params.require(:reservation_policy).permit(
      :reservation_enabled,
      :advance_booking_days, :minimum_advance_hours, :min_party_size, :max_party_size,
      :max_bookings_per_phone, :phone_limit_period_days,
      :deposit_required, :deposit_per_person, :deposit_amount,
      :no_show_policy, :modification_policy, :special_rules, :cancellation_hours,
      :unlimited_dining_time, :default_dining_duration_minutes, :buffer_time_minutes,
      :allow_table_combinations, :max_combination_tables
    )
  end
end
