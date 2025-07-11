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
    if has_capacity
      availability_service = RestaurantAvailabilityService.new(@restaurant)
      unavailable_dates = availability_service.get_unavailable_dates_optimized(party_size, max_days)
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
    adults = params[:adults]&.to_i || party_size
    children = params[:children].to_i

    Rails.logger.info "Available dates request: party_size=#{party_size}, adults=#{adults}, children=#{children}"

    if party_size <= 0 || party_size > 12
      render json: { error: '人數必須在 1-12 人之間' }, status: :bad_request
      return
    end

    # 使用新的service處理業務邏輯
    availability_service = RestaurantAvailabilityService.new(@restaurant)
    has_capacity = @restaurant.has_capacity_for_party_size?(party_size)

    available_dates = if has_capacity
                        availability_service.get_available_dates(party_size, adults, children)
                      else
                        []
                      end

    full_booked_until = if has_capacity && available_dates.empty?
                          availability_service.calculate_full_booked_until(party_size, adults, children)
                        end

    business_periods = @restaurant.business_periods.active

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
    phone_number = params[:phone]
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

    # 強化日期檢查：不能預定當天或過去的日期
    if date <= Date.current
      Rails.logger.info "Rejected date #{date} because it's not after #{Date.current} (same-day booking disabled)"
      render json: { error: '不可預定當天或過去的日期' }, status: :unprocessable_entity
      return
    end

    # 檢查預約天數限制
    advance_booking_days = reservation_policy&.advance_booking_days || 30
    max_booking_date = Date.current + advance_booking_days.days

    if date > max_booking_date
      Rails.logger.info "Rejected date #{date} because it's beyond advance booking limit of #{advance_booking_days} days"
      render json: { error: '超出預約範圍' }, status: :unprocessable_entity
      return
    end

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

    # 使用新的service處理業務邏輯
    availability_service = RestaurantAvailabilityService.new(@restaurant)
    time_slots = availability_service.get_available_times(date, party_size, adults, children)

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

  def check_reservation_enabled
    reservation_policy = @restaurant.reservation_policy

    return if reservation_policy&.accepts_online_reservations?

    render json: {
      reservation_enabled: false,
      message: "很抱歉，#{@restaurant.name} 目前暫停接受線上訂位。如需訂位，請直接致電餐廳洽詢。"
    }, status: :service_unavailable
  end
end
