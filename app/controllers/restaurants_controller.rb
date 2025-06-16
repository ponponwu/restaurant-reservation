class RestaurantsController < ApplicationController
  before_action :set_restaurant
  before_action :check_reservation_enabled, only: [:available_days, :available_dates, :available_times]
  
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
    party_size = 2 if party_size <= 0  # 預設 2 人
    
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
    if has_capacity
      unavailable_dates = get_unavailable_dates_optimized(party_size, max_days)
    end
    
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
    children = params[:children]&.to_i || 0
    
    Rails.logger.info "Available dates request: party_size=#{party_size}, adults=#{adults}, children=#{children}"
    
    if party_size <= 0 || party_size > 12
      render json: { error: '人數必須在 1-12 人之間' }, status: :bad_request
      return
    end
    
    # 檢查餐廳是否有足夠容量的桌位
    has_capacity = @restaurant.has_capacity_for_party_size?(party_size)
    
    # 獲取接下來 60 天的可預約日期
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
    else
      nil
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
  rescue => e
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
    children = params[:children]&.to_i || 0
    
    Rails.logger.info "Available times request: date=#{date}, party_size=#{party_size}, adults=#{adults}, children=#{children}, phone=#{phone_number}"
    
    if party_size <= 0 || party_size > 12
      Rails.logger.info "Rejected party_size #{party_size} (out of range)"
      render json: { error: '人數必須在 1-12 人之間' }, status: :bad_request
      return
    end
    
    Rails.logger.info "Party size check passed"
    
    # 強化日期檢查：不能預定當天或過去的日期
    if date <= Date.current
      Rails.logger.info "Rejected date #{date} because it's not after #{Date.current} (same-day booking disabled)"
      render json: { error: '不可預定當天或過去的日期' }, status: :unprocessable_entity
      return
    end
    
    Rails.logger.info "Date check passed"
    
    # 檢查手機號碼訂位限制
    reservation_policy = @restaurant.reservation_policy
    phone_limit_exceeded = false
    phone_limit_message = nil
    remaining_bookings = nil
    
    if phone_number.present? && reservation_policy
      phone_limit_exceeded = reservation_policy.phone_booking_limit_exceeded?(phone_number)
      remaining_bookings = reservation_policy.remaining_bookings_for_phone(phone_number)
      
      if phone_limit_exceeded
        phone_limit_message = "訂位次數已達上限。"
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
  rescue => e
    Rails.logger.error "Available times error: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { error: "伺服器錯誤: #{e.message}" }, status: :internal_server_error
  end
  
  private
  
  def set_restaurant
    @restaurant = Restaurant.includes(
      :business_periods, 
      :closure_dates, 
      :reservation_policy,
      restaurant_tables: [:table_group],
      reservations: [:business_period, :table, table_combination: :restaurant_tables]
    ).find_by!(slug: params[:slug])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: '找不到指定的餐廳'
  end

  def get_available_dates_with_allocator(party_size, adults, children)
    available_dates = []
    start_date = Date.current + 1.day  # 從明天開始，不能預定當天
    end_date = 60.days.from_now
    
    (start_date..end_date).each do |date|
      # 跳過公休日
      next if @restaurant.closed_on_date?(date)
      next unless @restaurant.has_business_period_on_date?(date)
      
      # 檢查當天是否有任何時段可以容納該人數
      if has_availability_on_date?(date, party_size, adults, children)
        available_dates << date.to_s
      end
    end
    
    available_dates
  end

  def get_available_times_with_allocator(date, party_size, adults, children)
    Rails.logger.info "Getting available times for date=#{date}, party_size=#{party_size}, adults=#{adults}, children=#{children}"
    
    time_slots = []
    
    # 使用餐廳的動態時間產生方法
    available_time_options = @restaurant.available_time_options_for_date(date)
    Rails.logger.info "Found #{available_time_options.size} time options"
    
    available_time_options.each do |time_option|
      Rails.logger.info "Checking time option: #{time_option[:time]}"
      
      # 使用桌位分配服務檢查可用性
      allocator = ReservationAllocatorService.new(
        restaurant: @restaurant,
        party_size: party_size,
        adults: adults,
        children: children,
        reservation_datetime: time_option[:datetime],
        business_period_id: time_option[:business_period_id]
      )
      
      availability = allocator.check_availability
      Rails.logger.info "Availability for #{time_option[:time]}: #{availability[:has_availability]}"
      
      if availability[:has_availability]
        time_slots << {
          time: time_option[:time],
          business_period_id: time_option[:business_period_id],
          available: true
        }
      end
    end
    
    Rails.logger.info "Returning #{time_slots.size} available time slots"
    time_slots
  end

  def has_availability_on_date?(date, party_size, adults, children)
    # 使用餐廳的動態時間產生方法
    available_time_options = @restaurant.available_time_options_for_date(date)
    
    available_time_options.each do |time_option|
      # 使用桌位分配服務檢查可用性
      allocator = ReservationAllocatorService.new(
        restaurant: @restaurant,
        party_size: party_size,
        adults: adults,
        children: children,
        reservation_datetime: time_option[:datetime],
        business_period_id: time_option[:business_period_id]
      )
      
      return true if allocator.check_availability[:has_availability]
    end
    
    false
  end

  def calculate_full_booked_until(party_size, adults, children)
    # 檢查接下來 90 天內第一個有空位的日期
    start_date = Date.current
    end_date = 90.days.from_now
    
    (start_date..end_date).each do |date|
      next if @restaurant.closed_on_date?(date)
      next unless @restaurant.has_business_period_on_date?(date)
      
      if has_availability_on_date?(date, party_size, adults, children)
        # 找到第一個有空位的日期，客滿時間就是前一天
        return (date - 1.day).to_s
      end
    end
    
    # 如果 90 天內都沒有空位，回傳 90 天後的日期
    end_date.to_s
  end

  def check_reservation_enabled
    reservation_policy = @restaurant.reservation_policy
    
    unless reservation_policy&.accepts_online_reservations?
      render json: { 
        error: reservation_policy&.reservation_disabled_message || "線上訂位功能暫停",
        reservation_enabled: false,
        message: "很抱歉，#{@restaurant.name} 目前暫停接受線上訂位。如需訂位，請直接致電餐廳洽詢。"
      }, status: :service_unavailable
    end
  end

  def get_unavailable_dates_optimized(party_size, max_days)
    unavailable_dates = []
    start_date = Date.current + 1.day
    end_date = start_date + max_days.days
    
    # 預載入所有相關資料，避免 N+1 查詢
    date_range = (start_date..end_date).to_a
    
    # 一次性預載入所有訂位資料
    all_reservations = @restaurant.reservations
                                 .where(status: %w[pending confirmed])
                                 .where('DATE(reservation_datetime) BETWEEN ? AND ?', start_date, end_date)
                                 .includes(:business_period, :table, table_combination: :restaurant_tables)
                                 .to_a
    
    # 按日期分組
    reservations_by_date = all_reservations.group_by { |r| r.reservation_datetime.to_date }
    
    # 預載入餐廳桌位資料
    restaurant_tables = @restaurant.restaurant_tables.active.available_for_booking
                                  .includes(:table_group)
                                  .to_a
    
    # 預載入營業時段資料
    business_periods_cache = @restaurant.business_periods.active.index_by(&:id)
    
    # 預載入休息日資料，避免在迴圈中重複查詢
    closure_dates = @restaurant.closure_dates
                              .where('date BETWEEN ? AND ? OR recurring = ?', start_date, end_date, true)
                              .to_a
    
    # 建立休息日快取
    closed_dates_cache = Set.new
    closure_dates.each do |closure|
      if closure.recurring?
        # 處理週期性休息日
        date_range.each do |date|
          closed_dates_cache.add(date) if date.wday == closure.weekday
        end
      else
        closed_dates_cache.add(closure.date)
      end
    end
    
    # 批量檢查每天的可用性
    date_range.each do |date|
      # 跳過公休日
      next if closed_dates_cache.include?(date)
      next unless business_periods_cache.values.any? { |bp| bp.operates_on_weekday?(date.wday) }
      
      # 檢查當天是否有任何時段可以容納該人數
      unless has_availability_on_date_cached?(
        date, 
        reservations_by_date[date] || [], 
        restaurant_tables, 
        business_periods_cache,
        party_size
      )
        unavailable_dates << date.to_s
      end
    end
    
    unavailable_dates
  end

  def has_availability_on_date_cached?(date, day_reservations, restaurant_tables, business_periods_cache, party_size)
    # 按需獲取時間選項，利用 Restaurant 模型的快取
    available_time_options = @restaurant.available_time_options_for_date(date)
    return false if available_time_options.empty?
    
    # 按營業時段分組訂位
    reservations_by_period = day_reservations.group_by(&:business_period_id)
    
    # 檢查是否有任何時段可用
    available_time_options.any? do |time_option|
      business_period_id = time_option[:business_period_id]
      datetime = time_option[:datetime]
      
      # 使用快取的營業時段資料
      business_period = business_periods_cache[business_period_id]
      next false unless business_period
      
      # 檢查該時段是否有可用桌位
      has_availability_for_slot_optimized?(
        restaurant_tables, 
        reservations_by_period[business_period_id] || [], 
        datetime, 
        party_size, 
        business_period_id
      )
    end
  end

  def has_availability_for_slot_optimized?(restaurant_tables, period_reservations, datetime, party_size, business_period_id)
    # 快取已計算的預訂桌位 ID，避免重複計算
    @reserved_table_ids_cache ||= {}
    cache_key = "#{business_period_id}_#{datetime.strftime('%Y%m%d_%H%M')}"
    
    reserved_table_ids = @reserved_table_ids_cache[cache_key] ||= 
      get_reserved_table_ids_for_period_optimized(period_reservations, datetime, business_period_id)
    
    # 過濾掉已被預訂的桌位
    available_tables = restaurant_tables.reject { |table| reserved_table_ids.include?(table.id) }
    
    # 檢查是否有適合的單一桌位
    suitable_table = available_tables.find { |table| table.suitable_for?(party_size) }
    return true if suitable_table
    
    # 檢查是否可以併桌（只在需要時才計算）
    if @restaurant.can_combine_tables? && party_size > 1
      combinable_tables = available_tables.select { |table| table.can_combine? }
      return has_combinable_tables_for_party?(combinable_tables, party_size)
    end
    
    false
  end

  def get_reserved_table_ids_for_period_optimized(period_reservations, datetime, business_period_id)
    reserved_table_ids = []
    
    period_reservations.each do |reservation|
      # 檢查時間衝突
      if has_time_conflict_optimized?(reservation, datetime, business_period_id)
        # 添加直接預訂的桌位
        reserved_table_ids << reservation.table_id if reservation.table_id
        
        # 添加併桌組合中的桌位
        if reservation.table_combination
          reservation.table_combination.restaurant_tables.each do |table|
            reserved_table_ids << table.id
          end
        end
      end
    end
    
    reserved_table_ids.compact.uniq
  end

  def has_time_conflict_optimized?(reservation, target_datetime, target_business_period_id)
    # 如果是無限時模式，檢查同一餐期的衝突
    if @restaurant.unlimited_dining_time?
      return reservation.business_period_id == target_business_period_id &&
             reservation.reservation_datetime.to_date == target_datetime.to_date
    end
    
    # 限時模式：檢查時間重疊
    duration_minutes = @restaurant.dining_duration_with_buffer
    return false unless duration_minutes
    
    reservation_start = reservation.reservation_datetime
    reservation_end = reservation_start + duration_minutes.minutes
    target_start = target_datetime
    target_end = target_start + duration_minutes.minutes
    
    # 檢查時間區間是否重疊
    !(reservation_end <= target_start || target_end <= reservation_start)
  end

  def has_combinable_tables_for_party?(combinable_tables, party_size)
    return false if combinable_tables.empty?
    
    # 按群組分組桌位
    tables_by_group = combinable_tables.group_by(&:table_group_id)
    
    tables_by_group.each do |group_id, group_tables|
      # 檢查該群組是否能組成適合的組合
      if can_form_suitable_combination?(group_tables, party_size)
        return true
      end
    end
    
    false
  end

  def can_form_suitable_combination?(group_tables, party_size)
    return false if group_tables.size < 2
    
    # 簡化版本：檢查最多3張桌子的組合
    max_tables = [@restaurant.max_tables_per_combination, group_tables.size].min
    
    # 按容量排序，優先使用較小的桌位
    sorted_tables = group_tables.sort_by(&:capacity)
    
    # 嘗試不同數量的桌位組合
    (2..max_tables).each do |table_count|
      sorted_tables.combination(table_count) do |combination|
        total_capacity = combination.sum(&:capacity)
        return true if total_capacity >= party_size
      end
    end
    
    false
  end
end 