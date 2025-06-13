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
    # 獲取週營業日設定 (0=日, 1=一, ..., 6=六)
    weekly = {}
    7.times { |i| weekly[i] = false }
    
    # 從營業時段中獲取營業日（使用 bitmask 效率更高）
    @restaurant.business_periods.active.each do |period|
      # 對每個週幾檢查 bitmask
      (0..6).each do |weekday|
        if period.operates_on_weekday?(weekday)
          weekly[weekday] = true
        end
      end
    end
    
    # 獲取特殊公休日（不包含每週重複的公休日）
    date_range = Date.current..(Date.current + 90.days)
    special_closure_dates = @restaurant.closure_dates
                                      .where(recurring: false)
                                      .where(date: date_range)
                                      .pluck(:date)
                                      .map(&:to_s)
    
    # 獲取最大預訂天數
    max_days = @restaurant.reservation_policy&.advance_booking_days || 30
    
    Rails.logger.info "🔥 Available days API - weekly: #{weekly}, special: #{special_closure_dates}, max_days: #{max_days}"
    
    render json: {
      weekly: weekly,
      special: special_closure_dates,
      max_days: max_days
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
    unless @restaurant.has_capacity_for_party_size?(party_size)
      render json: { 
        available_dates: [],
        full_booked_until: nil,
        business_periods: []
      }
      return
    end
    
    # 獲取接下來 60 天的可預約日期
    available_dates = get_available_dates_with_allocator(party_size, adults, children)
    business_periods = @restaurant.business_periods.active
    
    # 如果沒有可預約日期，計算客滿到什麼時候
    full_booked_until = if available_dates.empty?
      calculate_full_booked_until(party_size, adults, children)
    else
      nil
    end
    
    render json: {
      available_dates: available_dates,
      full_booked_until: full_booked_until,
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
        phone_limit_message = "訂位次數已達上限。#{reservation_policy.formatted_phone_limit_policy}。您目前剩餘 #{remaining_bookings} 次訂位機會。"
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
    @restaurant = Restaurant.includes(:business_periods, :closure_dates)
                           .find_by!(slug: params[:slug])
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
end 