class RestaurantsController < ApplicationController
  before_action :set_restaurant
  before_action :check_reservation_enabled, only: %i[available_days available_dates available_times]

  # 明確載入服務類別
  unless defined?(ReservationAllocatorService)
    require_dependency Rails.root.join('app', 'services', 'reservation_allocator_service')
  end

  def show
    @business_periods = @restaurant.business_periods.active.includes(:reservation_slots)
    @today = Date.current

    # 計算人數選擇範圍
    policy = @restaurant.reservation_policy
    @min_party_size = policy&.min_party_size || 1
    @max_party_size = policy&.max_party_size || 10

    # 前台顯示的最大人數比設定值少1（如您要求的）
    @display_max_party_size = [@max_party_size - 1, @min_party_size].max
  end

  # 新增：獲取餐廳營業日資訊 (for flatpickr)
  def available_days
    party_size = params[:party_size].to_i
    party_size = 2 if party_size <= 0 # 預設 2 人

    # 獲取最大預訂天數
    max_days = @restaurant.reservation_policy&.advance_booking_days || 30

    # 檢查餐廳是否有足夠容量的桌位
    has_capacity = @restaurant.has_capacity_for_party_size?(party_size)

    # 獲取週營業日設定 (0=日, 1=一, ..., 6=六)
    weekly_closures = []
    7.times do |weekday|
      has_business_on_weekday = @restaurant.business_periods.active.any? do |period|
        period.operates_on_weekday?(weekday)
      end
      weekly_closures << weekday unless has_business_on_weekday
    end

    # 獲取特殊公休日
    date_range = Date.current..(Date.current + max_days.days)
    special_closure_dates = @restaurant.closure_dates
      .where(recurring: false)
      .where(date: date_range)
      .pluck(:date)
      .map(&:to_s)

    # 如果餐廳有容量，檢查實際可用日期（優化版本）
    unavailable_dates = []
    unavailable_dates = get_unavailable_dates_optimized(party_size, max_days) if has_capacity

    # 合併所有不可用日期
    all_special_closures = (special_closure_dates + unavailable_dates).uniq

    Rails.logger.info "🔥 Available days API - party_size: #{party_size}, has_capacity: #{has_capacity}, unavailable: #{unavailable_dates.size}"

    render json: {
      weekly_closures: weekly_closures,
      special_closures: all_special_closures,
      max_days: max_days,
      has_capacity: has_capacity
    }
  end

  def available_dates
    party_size = params[:party_size].to_i

    # 如果沒有提供 adults 和 children，則使用 party_size 作為 adults
    adults = params[:adults]&.to_i || party_size
    children = params[:children].to_i

    Rails.logger.info "Available dates request: party_size=#{party_size}, adults=#{adults}, children=#{children}"

    if party_size <= 0 || party_size > 12
      render json: { error: '人數必須在 1-12 人之間' }, status: :bad_request
      return
    end

    # 檢查餐廳是否有足夠容量的桌位
    has_capacity = @restaurant.has_capacity_for_party_size?(party_size)

    # 獲取接下來 餐廳可預訂天數 的可預約日期
    available_dates = if has_capacity
                        get_available_dates_with_allocator(party_size, adults, children)
                      else
                        []
                      end

    business_periods = @restaurant.business_periods.active

    # 只有在餐廳有足夠容量但沒有可預約日期時，才計算客滿到什麼時候
    # 如果餐廳沒有足夠容量的桌位，則不顯示額滿訊息
    full_booked_until = if has_capacity && available_dates.empty?
                          calculate_full_booked_until(party_size, adults, children)
                        end

    render json: {
      available_dates: available_dates,
      full_booked_until: full_booked_until,
      has_capacity: has_capacity,
      business_periods: business_periods.map do |bp|
        {
          id: bp.id,
          name: bp.name,
          start_time: bp.start_time.strftime('%H:%M'),
          end_time: bp.end_time.strftime('%H:%M')
        }
      end
    }
  rescue StandardError => e
    Rails.logger.error "Available dates error: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { error: "伺服器錯誤: #{e.message}" }, status: :internal_server_error
  end

  def available_times
    begin
      date = Date.parse(params[:date])
    rescue ArgumentError => e
      render json: { error: "日期格式錯誤: #{e.message}" }, status: :bad_request
      return
    end

    party_size = params[:party_size].to_i
    phone_number = params[:phone] # 添加手機號碼參數

    # 如果沒有提供 adults 和 children，則使用 party_size 作為 adults
    adults = params[:adults]&.to_i || party_size
    children = params[:children].to_i

    Rails.logger.info "Available times request: date=#{date}, party_size=#{party_size}, adults=#{adults}, children=#{children}, phone=#{phone_number}"

    # 檢查餐廳設定的人數限制
    reservation_policy = @restaurant.reservation_policy
    min_party_size = reservation_policy&.min_party_size || 1
    max_party_size = reservation_policy&.max_party_size || 12

    if party_size <= 0 || party_size < min_party_size || party_size > max_party_size
      Rails.logger.info "Rejected party_size #{party_size} (out of range #{min_party_size}-#{max_party_size})"
      render json: { error: '人數超出限制' }, status: :unprocessable_entity
      return
    end

    Rails.logger.info 'Party size check passed'

    # 強化日期檢查：不能預定當天或過去的日期
    if date <= Date.current
      Rails.logger.info "Rejected date #{date} because it's not after #{Date.current} (same-day booking disabled)"
      render json: { error: '不可預定當天或過去的日期' }, status: :unprocessable_entity
      return
    end

    Rails.logger.info 'Date check passed'

    # 檢查預約天數限制
    advance_booking_days = reservation_policy&.advance_booking_days || 30
    max_booking_date = Date.current + advance_booking_days.days
    
    if date > max_booking_date
      Rails.logger.info "Rejected date #{date} because it's beyond advance booking limit of #{advance_booking_days} days"
      render json: { error: '超出預約範圍' }, status: :unprocessable_entity
      return
    end

    Rails.logger.info 'Advance booking check passed'

    # 檢查手機號碼訂位限制
    phone_limit_exceeded = false
    phone_limit_message = nil
    remaining_bookings = nil

    if phone_number.present? && reservation_policy
      phone_limit_exceeded = reservation_policy.phone_booking_limit_exceeded?(phone_number)
      remaining_bookings = reservation_policy.remaining_bookings_for_phone(phone_number)

      if phone_limit_exceeded
        phone_limit_message = '訂位失敗，請聯繫餐廳'
        Rails.logger.info "Phone booking limit exceeded for #{phone_number}"
      end
    end

    # 檢查餐廳當天是否營業
    Rails.logger.info "Checking if restaurant is closed on #{date}"
    if @restaurant.closed_on_date?(date)
      Rails.logger.info "Restaurant is closed on #{date}"
      render json: {
        available_times: [],
        message: '餐廳當天公休',
        phone_limit_exceeded: phone_limit_exceeded,
        phone_limit_message: phone_limit_message,
        remaining_bookings: remaining_bookings
      }
      return
    end

    Rails.logger.info "Restaurant is open on #{date}, getting time slots"

    # 獲取當天的營業時段和可用時間
    time_slots = get_available_times_with_allocator(date, party_size, adults, children)

    Rails.logger.info "Got #{time_slots.size} time slots, rendering response"

    render json: {
      available_times: time_slots.sort_by { |slot| slot[:time] },
      phone_limit_exceeded: phone_limit_exceeded,
      phone_limit_message: phone_limit_message,
      remaining_bookings: remaining_bookings || reservation_policy&.max_bookings_per_phone
    }
  rescue StandardError => e
    Rails.logger.error "Available times error: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { error: "伺服器錯誤: #{e.message}" }, status: :internal_server_error
  end

  private

  # 快取查詢結果以避免重複資料庫查詢
  def cached_reservations_for_date_range(start_date, end_date)
    cache_key = "#{start_date}_#{end_date}"
    @reservations_cache ||= {}
    
    return @reservations_cache[cache_key] if @reservations_cache[cache_key]
    
    # 簡化策略：只在需要時才載入table_combinations
    # 大部分reservation都沒有table_combination，所以先不載入
    @reservations_cache[cache_key] = @restaurant.reservations
      .where(status: %w[pending confirmed])
      .where('DATE(reservation_datetime) BETWEEN ? AND ?', start_date, end_date)
      .includes(:business_period, :table)
      .to_a
  end

  def cached_reservations_for_date(date)
    # 如果已經有包含該日期的範圍查詢快取，則從中過濾
    @reservations_cache&.each do |cache_key, reservations|
      start_date_str, end_date_str = cache_key.split('_')
      start_date = Date.parse(start_date_str)
      end_date = Date.parse(end_date_str)
      
      if date >= start_date && date <= end_date
        return reservations.select { |r| r.reservation_datetime.to_date == date }
      end
    end
    
    # 如果沒有範圍快取，則建立單日快取
    cache_key = date.to_s
    @reservations_cache ||= {}
    
    return @reservations_cache[cache_key] if @reservations_cache[cache_key]
    
    @reservations_cache[cache_key] = @restaurant.reservations
      .where(status: %w[pending confirmed])
      .where('DATE(reservation_datetime) = ?', date)
      .includes(:business_period, :table)
      .to_a
  end

  # 懶載入table_combinations：只在需要時才查詢
  def ensure_table_combinations_loaded(reservations)
    return if @table_combinations_loaded
    
    reservation_ids = reservations.map(&:id)
    return if reservation_ids.empty?
    
    # 批次載入所有table_combinations
    table_combinations = TableCombination
      .where(reservation_id: reservation_ids)
      .includes(table_combination_tables: :restaurant_table)
      .index_by(&:reservation_id)
    
    # 手動設定關聯以避免額外查詢
    reservations.each do |reservation|
      if table_combinations[reservation.id]
        reservation.association(:table_combination).target = table_combinations[reservation.id]
        reservation.association(:table_combination).set_inverse_instance(table_combinations[reservation.id])
      end
    end
    
    @table_combinations_loaded = true
  end

  def set_restaurant
    @restaurant = Restaurant.includes(
      :business_periods,
      :restaurant_tables,
      :table_groups,
      :closure_dates,
      :reservation_policy
    ).find_by!(slug: params[:slug])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: '找不到指定的餐廳'
  end

  def get_available_dates_with_allocator(party_size, _adults, _children)
    available_dates = []
    start_date = Date.current
    advance_booking_days = @restaurant.reservation_policy&.advance_booking_days || 30
    end_date = start_date + advance_booking_days.days

    # 在迴圈外初始化，避免重複建立和查詢
    availability_service = AvailabilityService.new(@restaurant)

    # 使用快取避免重複查詢
    all_reservations = cached_reservations_for_date_range(start_date, end_date)

    # 預載入餐廳桌位資料（只查詢一次）
    restaurant_tables = @restaurant.restaurant_tables.active.available_for_booking
      .includes(:table_group)
      .to_a

    # 預載入營業時段資料
    business_periods_cache = @restaurant.business_periods.active.index_by(&:id)

    (start_date..end_date).each do |date|
      # 跳過今天，不允許當天預訂
      next if date <= Date.current
      
      # 過濾出當天的訂位（在記憶體中過濾，不重新查詢）
      day_reservations = all_reservations.select { |r| r.reservation_datetime.to_date == date }

      # 使用 AvailabilityService 的方法檢查可用性
      next unless availability_service.has_availability_on_date_cached?(
        date,
        day_reservations,
        restaurant_tables,
        business_periods_cache,
        party_size
      )

      available_dates << date.to_s
    end

    available_dates
  end

  def get_available_times_with_allocator(date, party_size, adults, children)
    Rails.logger.info "Getting available times for date=#{date}, party_size=#{party_size}, adults=#{adults}, children=#{children}"

    available_times = []
    target_date = date.is_a?(Date) ? date : Date.parse(date.to_s)

    # 使用餐廳的動態時間產生方法
    available_time_options = @restaurant.available_time_options_for_date(target_date)

    # 在迴圈外初始化，避免重複建立和查詢
    availability_service = AvailabilityService.new(@restaurant)

    # 使用快取避免重複查詢
    day_reservations = cached_reservations_for_date(target_date)

    # 預載入餐廳桌位資料（只查詢一次）
    restaurant_tables = @restaurant.restaurant_tables.active.available_for_booking
      .includes(:table_group)
      .to_a

    available_time_options.each do |time_option|
      datetime = time_option[:datetime]
      business_period_id = time_option[:business_period_id]

      # 按營業時段分組訂位（在迴圈內過濾，但不重新查詢）
      period_reservations = day_reservations.select { |r| r.business_period_id == business_period_id }

      # 檢查該時段是否有可用桌位
      next unless availability_service.has_availability_for_slot_optimized?(
        restaurant_tables,
        period_reservations,
        datetime,
        party_size,
        business_period_id
      )

      available_times << {
        time: datetime.strftime('%H:%M'),
        datetime: datetime.iso8601,
        business_period_id: business_period_id
      }
    end

    Rails.logger.info "Found #{available_times.size} available times"
    available_times
  end

  def has_availability_on_date?(date, party_size, _adults, _children)
    # 使用餐廳的動態時間產生方法
    available_time_options = @restaurant.available_time_options_for_date(date)
    return false if available_time_options.empty?

    # 使用 AvailabilityService 檢查可用性
    availability_service = AvailabilityService.new(@restaurant)

    # 使用快取避免重複查詢
    day_reservations = cached_reservations_for_date(date)

    # 預載入餐廳桌位資料
    restaurant_tables = @restaurant.restaurant_tables.active.available_for_booking
      .includes(:table_group)
      .to_a

    # 預載入營業時段資料
    business_periods_cache = @restaurant.business_periods.active.index_by(&:id)

    # 使用 AvailabilityService 的方法檢查可用性
    availability_service.has_availability_on_date_cached?(
      date,
      day_reservations,
      restaurant_tables,
      business_periods_cache,
      party_size
    )
  end

  def calculate_full_booked_until(party_size, _adults, _children)
    # 檢查接下來可預約天數內第一個有空位的日期
    start_date = Date.current
    advance_booking_days = @restaurant.reservation_policy&.advance_booking_days || 30
    end_date = start_date + advance_booking_days.days

    Rails.logger.info "🔍 calculate_full_booked_until: party_size=#{party_size}, start_date=#{start_date}, end_date=#{end_date}, advance_booking_days=#{advance_booking_days}"

    # 在迴圈外初始化，避免重複建立和查詢
    availability_service = AvailabilityService.new(@restaurant)

    # 使用快取避免重複查詢
    all_reservations = cached_reservations_for_date_range(start_date, end_date)

    # 預載入餐廳桌位資料（只查詢一次）
    restaurant_tables = @restaurant.restaurant_tables.active.available_for_booking
      .includes(:table_group)
      .to_a

    # 預載入營業時段資料
    business_periods_cache = @restaurant.business_periods.active.index_by(&:id)

    (start_date..end_date).each do |date|
      # 跳過今天，不允許當天預訂
      next if date <= Date.current
      
      # 過濾出當天的訂位（在記憶體中過濾，不重新查詢）
      day_reservations = all_reservations.select { |r| r.reservation_datetime.to_date == date }

      # 使用 AvailabilityService 的方法檢查可用性
      if availability_service.has_availability_on_date_cached?(
        date,
        day_reservations,
        restaurant_tables,
        business_periods_cache,
        party_size
      )
        Rails.logger.info "🔍 Found first available date: #{date}"
        return date
      end
    end

    # 如果可預約天數內都沒有空位，回傳最後一天
    end_date
  end

  def check_reservation_enabled
    reservation_policy = @restaurant.reservation_policy

    return if reservation_policy&.accepts_online_reservations?

    render json: {
      reservation_enabled: false,
      message: "很抱歉，#{@restaurant.name} 目前暫停接受線上訂位。如需訂位，請直接致電餐廳洽詢。"
    }, status: :service_unavailable
  end

  def get_unavailable_dates_optimized(party_size, max_days)
    # 使用 AvailabilityService 處理
    availability_service = AvailabilityService.new(@restaurant)
    availability_service.get_unavailable_dates_optimized(party_size, max_days)
  end
end
