class Admin::RestaurantSettings::RestaurantSettingsController < AdminController
  before_action :set_restaurant
  before_action :set_closure_dates, only: %i[closure_dates create_closure_date]
  before_action :set_reservation_policy, only: %i[index reservation_policies update_reservation_policy]
  before_action :set_operating_hours,
                only: %i[restaurant_settings update_restaurant_settings toggle_day_status]

  def index
    @stats = calculate_stats
  end

  def reservation_periods
    @reservation_periods = @restaurant.reservation_periods.includes(:reservation_slots)
  end

  def closure_dates
    # @closure_dates 已在 before_action 中設定
    @reservation_periods = @restaurant.reservation_periods.includes(:reservation_slots).active.ordered

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
                                                   }), status: :unprocessable_entity
        end
        format.html { render :reservation_policies, status: :unprocessable_entity }
      end
    end
  end

  # 週別營業時段編輯
  def edit_weekly_day
    @weekday = params[:weekday].to_i
    @chinese_name = ReservationPeriod::CHINESE_WEEKDAYS[@weekday]
    @periods = @restaurant.reservation_periods.for_weekday(@weekday).default_weekly.active
    @current_mode = determine_current_mode(@periods)

    respond_to do |format|
      format.html { render partial: 'weekly_reservation_periods_edit_modal', layout: false }
    end
  end

  # 週別營業時段更新
  def update_weekly_day
    weekday = params[:weekday].to_i
    mode = params[:mode] || params[:operation_mode] # 支援舊的參數名稱
    periods_params = params[:periods] || []

    ActiveRecord::Base.transaction do
      # 刪除該星期幾現有的預設時段
      @restaurant.reservation_periods.for_weekday(weekday).default_weekly.destroy_all

      # 同時刪除該星期幾的公休設定（如果存在）
      @restaurant.closure_dates.where(recurring: true, weekday: weekday).destroy_all

      case mode
      when 'twenty_four_hours'
        # 24小時營業：創建一個24小時時段
        @restaurant.reservation_periods.create!(
          name: '24小時營業',
          start_time: Time.zone.parse('00:00'),
          end_time: Time.zone.parse('23:59'),
          weekday: weekday,
          reservation_interval_minutes: 60
        )
      when 'custom_hours', nil
        # 自訂時段：創建多個時段（如果沒有指定模式，預設為自訂時段）
        periods_params.each do |period_param|
          @restaurant.reservation_periods.create!(
            name: period_param[:name] || '自訂時段',
            start_time: Time.zone.parse(period_param[:start_time]),
            end_time: Time.zone.parse(period_param[:end_time]),
            weekday: weekday,
            reservation_interval_minutes: period_param[:interval].to_i
          )
        end
      when 'closed'
        # 不開放：創建公休設定
        @restaurant.closure_dates.create!(
          date: Date.current.beginning_of_week + weekday.days,
          reason: "每週#{ReservationPeriod::CHINESE_WEEKDAYS[weekday]}固定公休",
          closure_type: 'regular',
          all_day: true,
          recurring: true,
          weekday: weekday
        )
      end
    end

    respond_to do |format|
      format.html { redirect_to admin_restaurant_settings_restaurant_closure_dates_path(@restaurant.slug), notice: '營業時段更新成功' }
      format.turbo_stream do
        @closure_dates = @restaurant.closure_dates.order(:date, :created_at)
        render turbo_stream: [
          turbo_stream.replace('weekly-closure-section',
                               partial: 'weekly_closure_section',
                               locals: { restaurant: @restaurant, closure_dates: @closure_dates }),
          turbo_stream.update('flash_messages',
                              partial: 'shared/flash_message',
                              locals: { message: '營業時段更新成功', type: 'success' })
        ]
      end
      format.json { render json: { success: true } }
    end
  rescue StandardError => e
    respond_to do |format|
      format.html { redirect_to admin_restaurant_settings_restaurant_closure_dates_path(@restaurant.slug), alert: "更新失敗: #{e.message}" }
      format.turbo_stream do
        render turbo_stream: turbo_stream.update('flash_messages',
                                                 partial: 'shared/flash_message',
                                                 locals: { message: "更新失敗: #{e.message}", type: 'error' })
      end
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
    end
  end

  # 複製週別營業時段
  def copy_weekly_day
    source_weekday = params[:source_weekday].to_i
    target_weekdays = params[:target_weekdays] || []

    ActiveRecord::Base.transaction do
      source_periods = @restaurant.reservation_periods.for_weekday(source_weekday).default_weekly.active

      target_weekdays.each do |target_weekday|
        weekday = target_weekday.to_i

        # 刪除目標星期幾現有的時段
        @restaurant.reservation_periods.for_weekday(weekday).default_weekly.destroy_all
        @restaurant.closure_dates.where(recurring: true, weekday: weekday).destroy_all

        # 複製源星期幾的時段
        source_periods.each do |source_period|
          @restaurant.reservation_periods.create!(
            name: source_period.name,
            start_time: source_period.start_time,
            end_time: source_period.end_time,
            weekday: weekday,
            reservation_interval_minutes: source_period.reservation_interval_minutes
          )
        end
      end
    end

    respond_to do |format|
      format.turbo_stream do
        @closure_dates = @restaurant.closure_dates.order(:date, :created_at)
        render turbo_stream: [
          turbo_stream.replace('weekly-closure-section',
                               partial: 'weekly_closure_section',
                               locals: { restaurant: @restaurant, closure_dates: @closure_dates }),
          turbo_stream.update('flash_messages',
                              partial: 'shared/flash_message',
                              locals: { message: '營業時段複製成功', type: 'success' })
        ]
      end
      format.json { render json: { success: true } }
    end
  rescue StandardError => e
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update('flash_messages',
                                                 partial: 'shared/flash_message',
                                                 locals: { message: "複製失敗: #{e.message}", type: 'error' })
      end
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
    end
  end

  def update_restaurant_settings
    operating_hours_params = params.require(:operating_hours)

    ActiveRecord::Base.transaction do
      operating_hours_params.each do |weekday, periods_params|
        weekday = weekday.to_i

        periods_params.each do |sort_order, period_params|
          # 跳過空的參數
          next if period_params.blank?

          sort_order = period_params[:sort_order].to_i

          # 找到或創建對應的營業時間記錄
          operating_hour = @restaurant.operating_hours.find_or_initialize_by(
            weekday: weekday,
            sort_order: sort_order
          )

          # 更新營業時間資料
          if period_params[:active] == '1'
            operating_hour.assign_attributes(
              open_time: Time.zone.parse(period_params[:open_time]),
              close_time: Time.zone.parse(period_params[:close_time])
            )
          else
            # 公休設定 - 直接刪除該時段
            operating_hour.destroy if operating_hour.persisted?
            next
          end

          # 保存更改
          operating_hour.save!
        end
      end

      flash[:success] = '餐廳營業時間已成功更新'
    end

    redirect_to admin_restaurant_settings_restaurant_restaurant_settings_path(@restaurant)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Operating hours update failed: #{e.record.errors.full_messages.join(', ')}"
    flash[:error] = "更新失敗: #{e.record.errors.full_messages.join(', ')}"
    redirect_to admin_restaurant_settings_restaurant_restaurant_settings_path(@restaurant)
  rescue StandardError => e
    Rails.logger.error "Operating hours update error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:error] = "更新失敗: #{e.message}"
    redirect_to admin_restaurant_settings_restaurant_restaurant_settings_path(@restaurant)
  end

  def toggle_day_status
    weekday = params[:weekday].to_i
    has_operating_hours = @restaurant.operating_hours.where(weekday: weekday).any?

    if has_operating_hours
      # 設為公休：刪除所有該日的時段
      @restaurant.operating_hours.where(weekday: weekday).destroy_all
    else
      # 設為營業：新增一個預設時段
      @restaurant.operating_hours.create!(
        weekday: weekday,
        open_time: Time.zone.parse('11:30'),
        close_time: Time.zone.parse('14:00'),
        sort_order: 1
      )
    end

    # 重新載入該日的資料
    @operating_hours_for_day = @restaurant.operating_hours.where(weekday: weekday).ordered.to_a

    respond_to do |format|
      format.turbo_stream do
        # 重新整理整個星期的區塊，包含按鈕狀態和時段列表
        render turbo_stream: turbo_stream.replace(
          "weekday_#{weekday}_section",
          partial: 'admin/restaurant_settings/restaurant_settings/weekday_day_section',
          locals: {
            restaurant: @restaurant,
            weekday: weekday,
            operating_hours: @operating_hours_for_day
          }
        )
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

  def set_operating_hours
    Rails.logger.info "set_operating_hours method called for restaurant: #{@restaurant.id}"

    begin
      # 載入現有的 operating hours 並按 weekday 分組
      existing_hours = @restaurant.operating_hours.ordered.to_a
      Rails.logger.info "Found #{existing_hours.size} existing operating hours"

      # 按 weekday 分組
      grouped_hours = existing_hours.group_by(&:weekday)
      Rails.logger.info "Grouped into #{grouped_hours.keys.size} weekdays"

      # 為每個 weekday 確保有對應的 operating hours
      @operating_hours = {}
      (0..6).each do |weekday|
        @operating_hours[weekday] = grouped_hours[weekday]
        # @operating_hours[weekday] = (grouped_hours[weekday].presence || [@restaurant.operating_hours.build(
        #   weekday: weekday,
        #   open_time: Time.zone.parse('11:30'),
        #   close_time: Time.zone.parse('14:00'),
        #   sort_order: 1
        # )])
      end

      Rails.logger.info "Created operating hours for #{@operating_hours.keys.size} weekdays"
      Rails.logger.info "Operating hours present: #{@operating_hours.present?}"
    rescue StandardError => e
      Rails.logger.error "Error in set_operating_hours: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  def calculate_stats
    {
      total_periods: @restaurant.reservation_periods.count,
      active_periods: @restaurant.reservation_periods.active.count,
      total_slots: @restaurant.reservation_periods.joins(:reservation_slots).count,
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
      :unlimited_dining_time, :default_dining_duration_minutes,
      :allow_table_combinations, :max_combination_tables
    )
  end

  def determine_current_mode(periods)
    return 'closed' if periods.empty?

    # 檢查是否為24小時營業
    if periods.length == 1 && periods.first.twenty_four_hours?
      'twenty_four_hours'
    else
      'custom_hours'
    end
  end
end
