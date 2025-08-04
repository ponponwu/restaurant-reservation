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

    # 設定參數並驗證
    unless setup_create_params
      @selected_date = begin
        Date.parse(params[:date])
      rescue StandardError
        Date.current
      end
      render :new, status: :unprocessable_entity
      return
    end

    # 檢查手機號碼訂位限制
    return unless validate_phone_booking_limit

    # 使用樂觀鎖機制
    result = create_reservation_with_optimistic_locking

    if result[:success]
      success_message = '訂位建立成功！'
      if @reservation.cancellation_token.present?
        # 優先使用短網址，失敗時降級到完整網址
        cancel_url = @reservation.short_cancellation_url ||
                     restaurant_reservation_cancel_url(@restaurant.slug, @reservation.cancellation_token)
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
      :reservation_periods,
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
                             @restaurant.reservation_periods.maximum(:updated_at)].compact.max

    "availability_status:#{@restaurant.id}:#{Date.current}:#{party_size}:#{restaurant_updated_at.to_i}:v4"
  end

  def build_slots_cache_key(date, party_size, adults, children)
    restaurant_updated_at = [@restaurant.updated_at,
                             @restaurant.reservation_periods.maximum(:updated_at)].compact.max

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
    @reservation_period_id = params[:reservation_period_id]

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
    @reservation_period_id = params[:reservation_period_id]

    # 驗證必要參數
    if @selected_time.blank?
      @reservation.errors.add(:base, '請選擇預約時間')
      return false
    end

    # 找到對應的預約時段ID（如果沒有提供的話）
    if @reservation_period_id.blank?
      @reservation_period_id = find_reservation_period_for_time(@selected_date, @selected_time)

      # 檢查是否為有效的自訂時段（reservation_period_id 為 nil 但時間有效）
      if @reservation_period_id.blank?
        # 檢查是否為特殊訂位日的有效時間
        special_date = @restaurant.special_date_for(@selected_date)
        if special_date&.custom_hours?
          # 驗證時間是否在自訂時段範圍內
          target_datetime = Time.zone.parse("#{@selected_date} #{@selected_time}")
          valid_custom_time = special_date.custom_periods.any? do |period|
            period_start = Time.zone.parse("#{@selected_date} #{period['start_time']}")
            period_end = Time.zone.parse("#{@selected_date} #{period['end_time']}")
            target_datetime >= period_start && target_datetime <= period_end
          end

          unless valid_custom_time
            @reservation.errors.add(:base, '所選時間無效，請重新選擇')
            return false
          end
          # 自訂時段的 reservation_period_id 保持為 nil
        else
          @reservation.errors.add(:base, '所選時間無效，請重新選擇')
          return false
        end
      end
    end

    @reservation.party_size = @adults + @children
    @reservation.adults_count = @adults
    @reservation.children_count = @children
    @reservation.reservation_datetime = Time.zone.parse("#{@selected_date} #{@selected_time}")
    @reservation.status = :confirmed
    @reservation.reservation_period_id = @reservation_period_id

    true
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

  # 使用樂觀鎖機制建立訂位（真正的樂觀鎖實現）
  def create_reservation_with_optimistic_locking
    max_retries = 3
    retries = 0

    begin
      # 執行樂觀鎖分配（內部已處理資料庫約束衝突）
      result = allocate_table_and_save_reservation

      # 成功時清除快取
      clear_availability_cache if result[:success]

      result
    rescue ActiveRecord::StaleObjectError => e
      # 真正的樂觀鎖衝突（版本不符）
      retries += 1
      if retries < max_retries
        Rails.logger.info "樂觀鎖版本衝突，重試第 #{retries} 次: #{e.message}"
        sleep(0.1 * (2**retries)) # 指數退避：0.2s, 0.4s, 0.8s
        @reservation.reload if @reservation.persisted?
        retry
      else
        Rails.logger.warn "樂觀鎖重試次數用盡: #{e.message}"
        { success: false, errors: ['該時段預訂踴躍，請稍後再試或選擇其他時間'] }
      end
    rescue StandardError => e
      Rails.logger.error "預訂創建錯誤: #{e.message}\n#{e.backtrace.join("\n")}"
      { success: false, errors: ['訂位處理時發生錯誤，請稍後再試'] }
    end
  end

  # 分配桌位並保存訂位（真正的樂觀鎖版本）
  def allocate_table_and_save_reservation
    # 樂觀鎖核心：依賴資料庫約束檢測衝突
    ActiveRecord::Base.transaction do
      # 使用樂觀鎖分配器（無鎖查詢）
      allocator = EnhancedReservationAllocatorService.new({
                                                            restaurant: @restaurant,
                                                            party_size: @reservation.party_size,
                                                            adults: @adults,
                                                            children: @children,
                                                            reservation_datetime: @reservation.reservation_datetime,
                                                            reservation_period_id: @reservation_period_id
                                                          })

      # 樂觀分配桌位（無鎖）
      allocated_table = allocator.allocate_table_with_optimistic_locking
      return { success: false, errors: ['該時段已無可用桌位，請選擇其他時間'] } unless allocated_table

      # 設置桌位到預訂
      @reservation.table = allocated_table.is_a?(Array) ? nil : allocated_table

      # 依賴 lock_version 和資料庫約束進行衝突檢測
      @reservation.save!

      # 處理併桌情況
      save_table_combination(allocated_table) if allocated_table.is_a?(Array)

      Rails.logger.info "訂位建立成功: #{@reservation.id}"

      # 訂位成功後發送確認簡訊
      send_reservation_confirmation_sms(@reservation)

      { success: true }
    end
  rescue ActiveRecord::RecordNotUnique => e
    # 資料庫約束衝突（桌位已被預訂）
    Rails.logger.info "資料庫約束衝突: #{e.message}"
    { success: false, errors: ['該時段已被其他顧客預訂，請選擇其他時間'] }
  rescue ActiveRecord::RecordInvalid => e
    # 驗證錯誤
    Rails.logger.error "預訂驗證失敗: #{e.message}"
    { success: false, errors: [@reservation.errors.full_messages.first || e.message] }
  rescue PG::NotNullViolation => e
    # PostgreSQL NOT NULL 約束違反，特別處理 reservation_period_id
    if e.message.include?('reservation_period_id')
      Rails.logger.error "預約時段ID為空: #{e.message}"
      { success: false, errors: ['預約時段資訊不完整，請重新選擇時間'] }
    else
      Rails.logger.error "資料庫約束錯誤: #{e.message}"
      { success: false, errors: ['預約資料不完整，請檢查所有必填欄位'] }
    end
  rescue StandardError => e
    Rails.logger.error "訂位處理錯誤: #{e.message}\n#{e.backtrace.join("\n")}"
    { success: false, errors: ['訂位處理時發生錯誤，請稍後再試'] }
  end

  # 保存併桌組合
  def save_table_combination(tables)
    combination = @reservation.build_table_combination(
      name: "併桌-#{tables.map(&:table_number).join('+')}",
      # party_size: @reservation.party_size,
      notes: '系統自動分配併桌'
    )

    combination.restaurant_tables = tables
    combination.save!
  end

  # 處理訂位建立失敗
  def handle_reservation_creation_failure(errors)
    # 檢查是否為併發衝突錯誤
    has_conflict_error = errors.any? do |error|
      error.include?('已被預訂') ||
        error.include?('衝突') ||
        error.include?('人數已滿') ||
        error.include?('重複預訂') ||
        error.include?('預訂人數眾多')
    end

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
    elsif has_conflict_error
      # 如果是併發衝突，提供更友善的訊息
      @reservation.errors.add(:base, '該時段預訂踴躍，請嘗試其他時間或稍後再試')
      # 未來可以在這裡加入建議替代時段的邏輯
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

  # 清除可用性相關快取（優化版本）
  def clear_availability_cache
    # 由於 cache key 已包含 restaurant_updated_at，大部分情況下會自動失效
    # 這裡只需要清除當天受直接影響的 cache

    target_date = Date.current

    # 計算餐廳設定的時間戳（用於建構正確的 cache key）
    restaurant_updated_at = [@restaurant.updated_at,
                             @restaurant.reservation_policy&.updated_at,
                             @restaurant.reservation_periods.maximum(:updated_at)].compact.max

    # 根據餐廳政策動態決定清除範圍，避免過度清除
    max_party_size = @restaurant.policy&.max_party_size || 12
    (1..max_party_size).each do |party_size|
      # 使用正確的 cache key 格式進行清除
      availability_key = "availability_status:#{@restaurant.id}:#{target_date}:#{party_size}:#{restaurant_updated_at.to_i}:v4"
      Rails.cache.delete(availability_key)

      # 清除可用時段快取（簡化組合）
      (0..party_size).each do |children|
        adults = party_size - children
        slots_key = "available_slots:#{@restaurant.id}:#{target_date}:#{party_size}:#{adults}:#{children}:#{restaurant_updated_at.to_i}:v2"
        Rails.cache.delete(slots_key)
      end
    end

    Rails.logger.info "Cleared availability cache for restaurant #{@restaurant.id} on #{target_date}"
  end

  # 根據日期和時間查找對應的預約時段ID
  def find_reservation_period_for_time(date, time_string)
    return nil if date.blank? || time_string.blank?

    begin
      target_datetime = Time.zone.parse("#{date} #{time_string}")

      # 檢查是否為特殊訂位日（自訂時段）
      special_date = @restaurant.special_date_for(date)
      if special_date&.custom_hours?
        # 使用新的方法查找對應的 ReservationPeriod
        period = special_date.find_reservation_period_for_time(time_string)
        return period&.id
      end

      # 常規日期：查找該日期和星期的預約時段
      periods = @restaurant.reservation_periods_for_date(date)

      periods.each do |period|
        # 檢查時間是否落在該時段範圍內
        start_time = period.local_start_time
        end_time = period.local_end_time

        # 將時間轉換為同一天進行比較
        period_start = Time.zone.parse("#{date} #{start_time.strftime('%H:%M')}")
        period_end = Time.zone.parse("#{date} #{end_time.strftime('%H:%M')}")

        # 檢查目標時間是否在時段範圍內
        return period.id if target_datetime >= period_start && target_datetime <= period_end
      end

      nil
    rescue StandardError => e
      Rails.logger.error "尋找預約時段ID時發生錯誤: #{e.message}"
      nil
    end
  end

  # 發送訂位確認簡訊（使用 Rails.logger 模擬）
  def send_reservation_confirmation_sms(reservation)
    return unless reservation.customer_phone.present?

    begin
      # 使用 Rails.logger 模擬簡訊發送過程
      Rails.logger.info '📱 [SMS模擬] 開始發送訂位確認簡訊'
      Rails.logger.info "📱 [SMS模擬] 收件人: #{reservation.customer_name} (#{reservation.customer_phone})"

      # 生成短網址
      short_url = reservation.short_cancellation_url
      cancel_url = short_url || reservation.cancellation_url

      # 建立簡訊內容
      restaurant = reservation.restaurant
      date = reservation.reservation_datetime.strftime('%m/%d')
      weekday = format_weekday_for_sms(reservation.reservation_datetime.wday)
      time = reservation.reservation_datetime.strftime('%H:%M')

      message = "您已預約【#{restaurant.name}】#{date}（#{weekday}）#{time}，#{reservation.party_size} 位。"
      message += "訂位資訊：#{cancel_url}" if cancel_url.present?

      Rails.logger.info "📱 [SMS模擬] 簡訊內容: #{message}"
      Rails.logger.info "📱 [SMS模擬] 內容長度: #{message.length} 字"
      Rails.logger.info "📱 [SMS模擬] 短網址: #{short_url.present? ? '✅ 已生成' : '❌ 使用原始網址'}"

      # 模擬發送成功
      Rails.logger.info '📱 [SMS模擬] ✅ 簡訊發送成功'

      # 創建 SMS 日誌記錄（如果 SmsLog 模型存在）
      if defined?(SmsLog)
        SmsLog.create!(
          reservation: reservation,
          phone_number: reservation.customer_phone,
          message_type: 'reservation_confirmation',
          content: message,
          status: 'sent',
          response_data: { simulation: true, timestamp: Time.current }.to_json
        )
        Rails.logger.info '📱 [SMS模擬] SMS 日誌已記錄'
      end
    rescue StandardError => e
      Rails.logger.error "📱 [SMS模擬] ❌ 簡訊發送失敗: #{e.message}"
      Rails.logger.error "📱 [SMS模擬] 錯誤堆疊: #{e.backtrace.first(3).join("\n")}"
    end
  end

  # 格式化星期顯示（簡訊用）
  def format_weekday_for_sms(wday)
    weekdays = %w[日 一 二 三 四 五 六]
    weekdays[wday]
  end
end
