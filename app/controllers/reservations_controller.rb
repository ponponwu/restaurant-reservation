class ReservationsController < ApplicationController
  before_action :set_restaurant
  before_action :check_reservation_enabled, except: [:available_slots]
  before_action :set_selected_date, only: %i[new create]

  # 明確載入服務類別
  unless defined?(ReservationAllocatorService)
    require_dependency Rails.root.join('app', 'services', 'reservation_allocator_service')
  end

  # 獲取預訂可用性狀態 - 重構版本
  def availability_status
    party_size = params[:party_size]&.to_i || 2

    # 檢查餐廳是否有足夠容量的桌位
    has_capacity = @restaurant.has_capacity_for_party_size?(party_size)

    # 改善快取策略：使用更長的快取時間，但包含更多影響因子
    cache_key = build_availability_cache_key(party_size)

    result = Rails.cache.fetch(cache_key, expires_in: 15.minutes) do
      calculate_availability_status(party_size, has_capacity)
    end

    # 添加容量資訊到結果中
    result[:has_capacity] = has_capacity

    render json: result
  rescue StandardError => e
    Rails.logger.error "Availability status error: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { error: "伺服器錯誤: #{e.message}" }, status: :internal_server_error
  end

  # 獲取指定日期的可用時間槽 - 重構版本
  def available_slots
    date, party_size, adults, children = parse_slot_params
    return if performed? # 如果參數驗證失敗，已經 render 了錯誤回應

    # 檢查餐廳當天是否營業
    if @restaurant.closed_on_date?(date)
      render json: { slots: [], message: '餐廳當天公休' }
      return
    end

    # 改善快取策略：包含更多影響因子
    cache_key = build_slots_cache_key(date, party_size, adults, children)

    slots = Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
      AvailabilityService.new(@restaurant).get_available_slots_by_period(
        date, party_size, adults, children
      )
    end

    render json: {
      slots: slots.sort_by { |slot| [slot[:period_name], slot[:time]] }
    }
  rescue StandardError => e
    Rails.logger.error "Available slots error: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { error: "伺服器錯誤: #{e.message}" }, status: :internal_server_error
  end

  def new
    @reservation = Reservation.new
    setup_new_reservation_params

    # 如果有指定人數，檢查是否有效
    if @selected_party_size.present?
      unless @restaurant.has_capacity_for_party_size?(@selected_party_size)
        redirect_to restaurant_public_path(@restaurant.slug),
                    alert: "無法為 #{@selected_party_size} 人安排訂位，請選擇其他人數。"
        return
      end
      @reservation.party_size = @selected_party_size
    end

    # 如果來自日曆選擇，顯示選擇的資訊
    return unless @selected_date && @selected_time

    @selected_datetime_display = format_selected_datetime(@selected_date, @selected_time)
  end

  def create
    # 重新檢查訂位功能是否啟用
    return unless validate_reservation_enabled

    @reservation = build_reservation
    setup_create_params

    # 檢查手機號碼訂位限制
    return unless validate_phone_booking_limit

    # 使用改善的併發控制
    result = create_reservation_with_concurrency_control

    if result[:success]
      success_message = '訂位建立成功！'
      if @reservation.cancellation_token.present?
        cancel_url = restaurant_reservation_cancel_url(@restaurant.slug, @reservation.cancellation_token)
        success_message += "<br/>如需取消訂位，請使用此連結：<a href='#{cancel_url}' class='text-blue-600 underline'>取消訂位</a>"
      end

      redirect_to restaurant_public_path(@restaurant.slug),
                  notice: success_message.html_safe
    else
      handle_reservation_creation_failure(result[:errors])
    end
  end

  private

  def set_restaurant
    @restaurant = Restaurant.includes(
      :reservation_policy,
      :business_periods,
      :closure_dates,
      restaurant_tables: :table_group
    ).find_by!(slug: params[:slug])
  end

  def set_selected_date
    @selected_date = begin
      Date.parse(params[:date])
    rescue StandardError
      Date.current
    end

    # 只對 new 動作進行基本的營業日檢查
    # create 動作的驗證交給模型層處理
    return unless action_name == 'new'

    # 檢查選擇的日期是否可訂位（基本檢查：營業日、公休日）
    return if @restaurant.open_on?(@selected_date)

    redirect_to restaurant_public_path(@restaurant.slug),
                alert: '所選日期無法訂位，請選擇其他日期。'
  end

  def reservation_params
    permitted_params = params.require(:reservation).permit(
      :customer_name, :customer_phone, :customer_email,
      :party_size, :special_requests
    )

    # Sanitize input to prevent XSS attacks
    if permitted_params[:customer_name].present?
      sanitized = ActionController::Base.helpers.strip_tags(permitted_params[:customer_name])
      sanitized = sanitized.gsub(/javascript:/i, '')
        .gsub(/on\w+=/i, '')
        .gsub(/alert\s*\(/i, '')
        .gsub(/<script[^>]*>/i, '')
        .gsub(%r{</script>}i, '')
      permitted_params[:customer_name] = sanitized
    end

    if permitted_params[:special_requests].present?
      sanitized = ActionController::Base.helpers.strip_tags(permitted_params[:special_requests])
      sanitized = sanitized.gsub(/javascript:/i, '')
        .gsub(/on\w+=/i, '')
        .gsub(/alert\s*\(/i, '')
        .gsub(/<script[^>]*>/i, '')
        .gsub(%r{</script>}i, '')
      permitted_params[:special_requests] = sanitized
    end

    permitted_params
  end

  def format_selected_datetime(date, time)
    weekdays = %w[日 一 二 三 四 五 六]
    weekday = weekdays[date.wday]
    "#{date.month}月#{date.day}日 (週#{weekday}) #{time}"
  end

  def check_reservation_enabled
    reservation_policy = @restaurant.reservation_policy

    return if reservation_policy&.accepts_online_reservations?

    respond_to do |format|
      format.html do
        flash[:alert] = if reservation_policy
                          reservation_policy.reservation_disabled_message
                        else
                          "很抱歉，#{@restaurant.name} 目前暫停接受線上訂位。如需訂位，請直接致電餐廳洽詢。"
                        end
        redirect_to restaurant_public_path(@restaurant.slug)
      end
      format.json do
        render json: {
          error: reservation_policy&.reservation_disabled_message || '線上訂位功能暫停',
          reservation_enabled: false
        }, status: :service_unavailable
      end
    end
  end

  # === 新增的私有方法 ===

  # 建立改善的快取鍵，包含更多影響因子
  def build_availability_cache_key(party_size)
    # 包含餐廳設定的最後更新時間，確保設定變更時快取失效
    restaurant_updated_at = [@restaurant.updated_at,
                             @restaurant.reservation_policy&.updated_at,
                             @restaurant.business_periods.maximum(:updated_at)].compact.max

    "availability_status:#{@restaurant.id}:#{Date.current}:#{party_size}:#{restaurant_updated_at.to_i}:v4"
  end

  def build_slots_cache_key(date, party_size, adults, children)
    restaurant_updated_at = [@restaurant.updated_at,
                             @restaurant.business_periods.maximum(:updated_at)].compact.max

    "available_slots:#{@restaurant.id}:#{date}:#{party_size}:#{adults}:#{children}:#{restaurant_updated_at.to_i}:v2"
  end

  # 計算可用性狀態
  def calculate_availability_status(party_size, has_capacity)
    return { unavailable_dates: [], fully_booked_until: nil } unless has_capacity

    start_date = Date.current
    end_date = 30.days.from_now

    # 使用服務類別來處理複雜的可用性計算
    availability_service = AvailabilityService.new(@restaurant)
    unavailable_dates = availability_service.check_availability_for_date_range(start_date, end_date, party_size)

    # 計算客滿到什麼時候
    fully_booked_until = calculate_fully_booked_until(unavailable_dates, end_date)

    {
      unavailable_dates: unavailable_dates,
      fully_booked_until: fully_booked_until
    }
  end

  def calculate_fully_booked_until(unavailable_dates, _max_date)
    return nil if unavailable_dates.empty?

    policy = @restaurant.reservation_policy
    max_advance_days = policy&.advance_booking_days || 30
    max_booking_date = Date.current + max_advance_days.days

    # 檢查是否在最大預訂天數內都客滿
    all_business_days = []
    ((Date.current + 1.day)..max_booking_date).each do |date|
      next if @restaurant.closed_on_date?(date)

      all_business_days << date.to_s
    end

    return unless all_business_days.all? { |date| unavailable_dates.include?(date) }

    max_booking_date.to_s
  end

  # 解析和驗證時間槽參數
  def parse_slot_params
    begin
      date = Date.parse(params[:date])
    rescue ArgumentError => e
      render json: { error: "日期格式錯誤: #{e.message}" }, status: :bad_request
      return [nil, nil, nil, nil]
    end

    adults    = (params[:adults]       || params[:adult_count]).to_i
    children  = (params[:children]     || params[:child_count]).to_i
    party_size = adults + children

    # 驗證人數
    policy = @restaurant.reservation_policy
    min_party_size = policy&.min_party_size || 1
    max_party_size = policy&.max_party_size || @restaurant.calculate_total_capacity

    if party_size <= 0 || party_size < min_party_size
      render json: { error: "人數必須至少 #{min_party_size} 人" }, status: :bad_request
      return [nil, nil, nil, nil]
    end

    if party_size > max_party_size
      render json: { error: "人數不能超過 #{max_party_size} 人" }, status: :bad_request
      return [nil, nil, nil, nil]
    end

    if date < Date.current
      render json: { error: '不能預約過去的日期' }, status: :bad_request
      return [nil, nil, nil, nil]
    end

    [date, party_size, adults, children]
  end

  # 設定新訂位的參數
  def setup_new_reservation_params
    @adults = params[:adults]&.to_i || 2
    @children = params[:children].to_i
    @selected_party_size = @adults + @children
    @selected_time = params[:time]
    @business_period_id = params[:period_id]

    @reservation.party_size = @selected_party_size if @selected_party_size.present?
  end

  # 建立訂位物件
  def build_reservation
    reservation = @restaurant.reservations.build(reservation_params)
    # 前台由控制器統一處理黑名單檢查，避免重複錯誤訊息
    reservation.skip_blacklist_validation = true
    reservation
  end

  # 設定建立訂位的參數
  def setup_create_params
    @adults = params[:adults]&.to_i || 2
    @children = params[:children].to_i
    @selected_time = params[:time_slot]
    @business_period_id = params[:business_period_id]

    @reservation.party_size = @adults + @children
    @reservation.adults_count = @adults
    @reservation.children_count = @children
    @reservation.reservation_datetime = Time.zone.parse("#{@selected_date} #{params[:time_slot]}")
    @reservation.status = :confirmed
    @reservation.business_period_id = @business_period_id
  end

  # 驗證訂位功能是否啟用
  def validate_reservation_enabled
    reservation_policy = @restaurant.reservation_policy
    unless reservation_policy&.accepts_online_reservations?
      flash[:alert] = reservation_policy&.reservation_disabled_message || '很抱歉，餐廳目前暫停接受線上訂位。'
      redirect_to restaurant_public_path(@restaurant.slug)
      return false
    end
    true
  end

  # 驗證手機號碼訂位限制和黑名單狀態
  def validate_phone_booking_limit
    customer_phone = @reservation.customer_phone
    reservation_policy = @restaurant.reservation_policy

    # 檢查黑名單狀態
    if customer_phone.present? && Blacklist.blacklisted_phone?(@restaurant, customer_phone)
      # 清空現有錯誤，確保不會有重複訊息
      @reservation.errors.clear
      @reservation.errors.add(:base, '訂位失敗，請聯繫餐廳')
      @selected_date = begin
        Date.parse(params[:date])
      rescue StandardError
        Date.current
      end
      render :new, status: :unprocessable_entity
      return false
    end

    # 檢查手機號碼訂位限制
    if customer_phone.present? && reservation_policy.phone_booking_limit_exceeded?(customer_phone)
      # 清空現有錯誤，確保不會有重複訊息
      @reservation.errors.clear
      @reservation.errors.add(:base, '訂位失敗，請聯繫餐廳')
      @selected_date = begin
        Date.parse(params[:date])
      rescue StandardError
        Date.current
      end
      render :new, status: :unprocessable_entity
      return false
    end

    true
  end

  # 使用改善的併發控制建立訂位
  def create_reservation_with_concurrency_control
    result = nil
    EnhancedReservationLockService.with_lock(@restaurant.id, @reservation.reservation_datetime,
                                             @reservation.party_size) do
      ActiveRecord::Base.transaction do
        result = allocate_table_and_save_reservation
        # 如果分配失敗，觸發 rollback
        raise ActiveRecord::Rollback unless result[:success]
      end
    end

    # 如果 transaction 被 rollback，result 仍然保有分配結果
    result || { success: false, errors: ['訂位處理失敗'] }
  rescue ConcurrentReservationError => e
    { success: false, errors: [e.message] }
  rescue StandardError => e
    Rails.logger.error "Reservation allocation error: #{e.message}\n#{e.backtrace.join("\n")}"
    { success: false, errors: ['訂位處理時發生錯誤，請稍後再試。'] }
  end

  # 分配桌位並保存訂位
  def allocate_table_and_save_reservation
    # 使用增強的併發控制分配器
    allocator = EnhancedReservationAllocatorService.new({
                                                          restaurant: @restaurant,
                                                          party_size: @reservation.party_size,
                                                          adults: @adults,
                                                          children: @children,
                                                          reservation_datetime: @reservation.reservation_datetime,
                                                          business_period_id: @business_period_id
                                                        })

    # 使用增強的可用性檢查（帶鎖定）
    availability_check = allocator.check_availability_with_lock
    unless availability_check[:has_availability]
      Rails.logger.warn "Enhanced availability check failed for reservation: #{@reservation.inspect}"
      return { success: false, errors: ['該時段已無可用桌位，請選擇其他時間。'] }
    end

    # 使用增強的分配方法（帶鎖定）
    allocated_table = allocator.allocate_table_with_lock
    if allocated_table.nil?
      Rails.logger.warn "Enhanced table allocation failed for reservation: #{@reservation.inspect}"
      return { success: false, errors: ['該時段已無可用桌位，請選擇其他時間。'] }
    end

    # 保存訂位
    save_result = save_reservation_with_table(allocated_table)

    if save_result[:success]
      # 清除相關快取
      clear_availability_cache
      Rails.logger.info "Reservation created successfully: #{@reservation.id}"
      { success: true }
    else
      Rails.logger.error "Failed to save reservation: #{save_result[:errors].join(', ')}"
      { success: false, errors: save_result[:errors] }
    end
  end

  # 保存訂位和桌位分配
  def save_reservation_with_table(allocated_table)
    if allocated_table.is_a?(Array)
      save_combination_reservation(allocated_table)
    else
      save_single_table_reservation(allocated_table)
    end
  end

  # 保存併桌訂位
  def save_combination_reservation(tables)
    # 使用事務確保原子性操作
    ActiveRecord::Base.transaction do
      combination = TableCombination.new(
        reservation: @reservation,
        name: "併桌 #{tables.map(&:table_number).join('+')}"
      )

      tables.each do |table|
        combination.table_combination_tables.build(restaurant_table: table)
      end

      @reservation.table = tables.first

      # 先保存訂位，再保存併桌組合
      unless @reservation.save
        Rails.logger.error "前台創建併桌訂位失敗 - 訂位保存失敗: #{@reservation.errors.full_messages.join(', ')}"
        raise ActiveRecord::Rollback
      end

      unless combination.save
        Rails.logger.error "前台創建併桌訂位失敗 - 併桌組合保存失敗: #{combination.errors.full_messages.join(', ')}"
        raise ActiveRecord::Rollback
      end

      Rails.logger.info "前台創建併桌訂位成功: #{tables.map(&:table_number).join(', ')}"
      { success: true }
    end
  rescue ActiveRecord::Rollback
    # 收集所有錯誤訊息
    all_errors = []
    all_errors.concat(@reservation.errors.full_messages) if @reservation.errors.any?
    all_errors.concat(combination.errors.full_messages) if defined?(combination) && combination&.errors&.any?

    # 檢查是否有敏感錯誤
    has_sensitive_error = all_errors.any? do |error|
      error.include?('黑名單') ||
        error.include?('無法進行訂位') ||
        error.include?('訂位失敗，請聯繫餐廳')
    end

    if has_sensitive_error
      { success: false, errors: ['訂位失敗，請聯繫餐廳'] }
    else
      { success: false, errors: all_errors.presence || ['併桌訂位建立失敗'] }
    end
  end

  # 保存單桌訂位
  def save_single_table_reservation(table)
    @reservation.table = table

    if @reservation.save
      { success: true }
    else
      Rails.logger.error "前台創建單桌訂位失敗: #{@reservation.errors.full_messages.join(', ')}"

      # 檢查是否有敏感錯誤並處理
      error_messages = @reservation.errors.full_messages
      has_sensitive_error = error_messages.any? do |error|
        error.include?('黑名單') ||
          error.include?('無法進行訂位') ||
          error.include?('訂位失敗，請聯繫餐廳')
      end

      if has_sensitive_error
        { success: false, errors: ['訂位失敗，請聯繫餐廳'] }
      else
        { success: false, errors: error_messages }
      end
    end
  end

  # 處理訂位建立失敗
  def handle_reservation_creation_failure(errors)
    # 檢查是否有敏感錯誤（黑名單、限制等）
    has_sensitive_error = errors.any? do |error|
      error.include?('黑名單') ||
        error.include?('無法進行訂位') ||
        error.include?('訂位失敗，請聯繫餐廳')
    end

    # 清空現有錯誤
    @reservation.errors.clear

    if has_sensitive_error
      # 如果有敏感錯誤，只顯示一個通用錯誤訊息
      @reservation.errors.add(:base, '訂位失敗，請聯繫餐廳')
    else
      # 如果沒有敏感錯誤，顯示原始錯誤訊息並去重
      errors.uniq.each { |error| @reservation.errors.add(:base, error) }
    end

    @selected_date = begin
      Date.parse(params[:date])
    rescue StandardError
      Date.current
    end
    render :new, status: :unprocessable_entity
  end

  # 清除可用性相關快取
  def clear_availability_cache
    # 清除當天和未來幾天的快取
    (Date.current..3.days.from_now.to_date).each do |date|
      Rails.cache.delete_matched("availability_status:#{@restaurant.id}:#{date}:*")
      Rails.cache.delete_matched("available_slots:#{@restaurant.id}:#{date}:*")
    end
  end
end
