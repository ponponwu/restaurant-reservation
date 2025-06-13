class ReservationsController < ApplicationController
  before_action :set_restaurant
  before_action :check_reservation_enabled
  before_action :set_selected_date, only: [:new, :create]
  
  # 明確載入服務類別
  unless defined?(ReservationAllocatorService)
    require_dependency Rails.root.join('app', 'services', 'reservation_allocator_service')
  end
  
  # 新增：獲取預訂可用性狀態
  def availability_status
    # 獲取接下來90天內預訂已滿的日期
    unavailable_dates = []
    start_date = Date.current
    end_date = 90.days.from_now
    
    # 檢查每天是否客滿 (簡化邏輯，實際可依據需求優化)
    (start_date..end_date).each do |date|
      next if @restaurant.closed_on_date?(date)
      
      # 檢查當天是否有任何時段可預訂 (假設人數為2)
      unless has_any_availability_on_date?(date)
        unavailable_dates << date.to_s
      end
    end
    
    # 計算客滿到什麼時候
    fully_booked_until = nil
    if unavailable_dates.any?
      # 找最後一個連續的客滿日期
      sorted_dates = unavailable_dates.sort
      # 簡化：取第一個不可用日期
      fully_booked_until = sorted_dates.first
    end
    
    render json: {
      unavailable_dates: unavailable_dates,
      fully_booked_until: fully_booked_until
    }
  rescue => e
    Rails.logger.error "Availability status error: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { error: "伺服器錯誤: #{e.message}" }, status: :internal_server_error
  end

  # 新增：獲取指定日期的可用時間槽 (按餐期分類)
  def available_slots
    begin
      date = Date.parse(params[:date])
    rescue ArgumentError => e
      render json: { error: "日期格式錯誤: #{e.message}" }, status: :bad_request
      return
    end
    
    adult_count = params[:adult_count].to_i
    child_count = params[:child_count].to_i
    party_size = adult_count + child_count
    
    if party_size <= 0 || party_size > 12
      render json: { error: '人數必須在 1-12 人之間' }, status: :bad_request
      return
    end
    
    if date < Date.current
      render json: { error: '不能預約過去的日期' }, status: :bad_request
      return
    end
    
    # 檢查餐廳當天是否營業
    if @restaurant.closed_on_date?(date)
      render json: { 
        slots: [],
        message: '餐廳當天公休'
      }
      return
    end
    
    # 獲取當天的可用時間槽，按餐期分類
    slots = get_available_slots_by_period(date, party_size, adult_count, child_count)
    
    render json: {
      slots: slots.sort_by { |slot| [slot[:period_name], slot[:time]] }
    }
  rescue => e
    Rails.logger.error "Available slots error: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { error: "伺服器錯誤: #{e.message}" }, status: :internal_server_error
  end
  
  def new
    @reservation = Reservation.new
    
    # 處理新的參數格式
    @adults = params[:adults]&.to_i || 2
    @children = params[:children]&.to_i || 0
    @selected_party_size = @adults + @children
    @selected_time = params[:time]
    @business_period_id = params[:period_id]
    
    # 如果有指定人數，檢查是否有效
    if @selected_party_size.present?
      unless @restaurant.has_capacity_for_party_size?(@selected_party_size)
        redirect_to restaurant_public_path(@restaurant.slug), 
                    alert: "無法為 #{@selected_party_size} 人安排訂位，請選擇其他人數。"
        return
      end
      @reservation.party_size = @selected_party_size
    end
    
    # 設定預設值到表單
    @reservation.party_size = @selected_party_size if @selected_party_size.present?
    
    # 如果來自日曆選擇，顯示選擇的資訊
    if @selected_date && @selected_time
      @selected_datetime_display = format_selected_datetime(@selected_date, @selected_time)
    end
  end
  
  def create
    # 重新檢查訂位功能是否啟用（防止 SSR 環境中資料尚未同步）
    reservation_policy = @restaurant.reservation_policy
    unless reservation_policy&.accepts_online_reservations?
      flash[:alert] = reservation_policy&.reservation_disabled_message || "很抱歉，餐廳目前暫停接受線上訂位。"
      redirect_to restaurant_public_path(@restaurant.slug)
      return
    end

    @reservation = @restaurant.reservations.build(reservation_params)
    
    # 設定人數
    @adults = params[:adults]&.to_i || 2
    @children = params[:children]&.to_i || 0
    @selected_time = params[:time_slot]
    @business_period_id = params[:business_period_id]
    @reservation.party_size = @adults + @children
    @reservation.adults_count = @adults
    @reservation.children_count = @children
    
    # 設定訂位時間
    @reservation.reservation_datetime = DateTime.parse("#{@selected_date} #{params[:time_slot]}")
    @reservation.status = :confirmed  # 直接設為已確認狀態
    @reservation.business_period_id = @business_period_id
    
    # 檢查手機號碼訂位限制
    customer_phone = @reservation.customer_phone
    if customer_phone.present? && reservation_policy.phone_booking_limit_exceeded?(customer_phone)
      remaining_bookings = reservation_policy.remaining_bookings_for_phone(customer_phone)
      limit_message = reservation_policy.formatted_phone_limit_policy
      
      @reservation.errors.add(:customer_phone, 
        "訂位次數已達上限。#{limit_message}。您目前剩餘 #{remaining_bookings} 次訂位機會。")
      @selected_date = Date.parse(params[:date]) rescue Date.current
      render :new, status: :unprocessable_entity
      return
    end

    # 使用事務處理確保桌位分配的原子性
    ActiveRecord::Base.transaction do
      # 使用桌位分配服務來分配桌位
      allocator = ReservationAllocatorService.new({
        restaurant: @restaurant,
        party_size: @reservation.party_size,
        adults: @adults,
        children: @children,
        reservation_datetime: @reservation.reservation_datetime,
        business_period_id: @business_period_id
      })
      
      # 檢查是否有可用桌位
      allocated_table = allocator.allocate_table
      
      if allocated_table.nil?
        @reservation.errors.add(:base, '該時段已無可用桌位，請選擇其他時間。')
        @selected_date = Date.parse(params[:date]) rescue Date.current
        render :new, status: :unprocessable_entity
        return
      end
      
      # 處理桌位分配
      if allocated_table.is_a?(Array)
        # 併桌情況 - 創建 TableCombination
        combination = TableCombination.new(
          reservation: @reservation,
          name: "併桌 #{allocated_table.map(&:table_number).join('+')}"
        )
        
        # 建立桌位關聯
        allocated_table.each do |table|
          combination.table_combination_tables.build(restaurant_table: table)
        end
        
        # 設定主桌位（用於相容性）
        @reservation.table = allocated_table.first
        
        # 保存訂位和併桌組合
        if @reservation.save && combination.save
          Rails.logger.info "前台創建併桌訂位成功: #{allocated_table.map(&:table_number).join(', ')}"
        else
          Rails.logger.error "前台創建併桌訂位失敗: #{@reservation.errors.full_messages.join(', ')}, #{combination.errors.full_messages.join(', ')}"
          raise ActiveRecord::Rollback
        end
      else
        # 單一桌位分配
        @reservation.table = allocated_table
        
        unless @reservation.save
          Rails.logger.error "前台創建單桌訂位失敗: #{@reservation.errors.full_messages.join(', ')}"
          raise ActiveRecord::Rollback
        end
      end
    end
    
    if @reservation.persisted?
      # 發送確認郵件或簡訊（之後實作）
      redirect_to restaurant_public_path(@restaurant.slug), 
                  notice: '訂位建立成功！'
    else
      @selected_date = Date.parse(params[:date]) rescue Date.current
      render :new, status: :unprocessable_entity
    end
  end
  
  private
  
  def set_restaurant
    @restaurant = Restaurant.find_by!(slug: params[:slug])
  end
  
  def set_selected_date
    @selected_date = Date.parse(params[:date]) rescue Date.current
    
    # 檢查選擇的日期是否可訂位
    unless @restaurant.open_on?(@selected_date)
      redirect_to restaurant_public_path(@restaurant.slug), 
                  alert: '所選日期無法訂位，請選擇其他日期。'
    end
  end
  
  def calculate_available_slots
    slots = []
    
    # 取得該日期的營業時段
    day_of_week = @selected_date.wday
    business_periods = @restaurant.business_periods.active
                                   .select { |bp| bp.days_of_week.include?(day_of_week.to_s) }
    
    business_periods.each do |period|
      period.reservation_slots.active.each do |slot|
        slot_time = slot.slot_time.strftime('%H:%M')
        slots << {
          time: slot_time,
          display: slot_time,
          period: period.name
        }
      end
    end
    
    slots.sort_by { |slot| slot[:time] }
  end
  
  def calculate_party_size_options
    policy = @restaurant.reservation_policy
    min_size = policy&.min_party_size || 1
    max_size = policy&.max_party_size || 10
    
    (min_size..max_size).to_a
  end
  
  def reservation_params
    params.require(:reservation).permit(
      :customer_name, :customer_phone, :customer_email,
      :party_size, :special_requests
    )
  end
  
  def format_selected_datetime(date, time)
    weekdays = %w[日 一 二 三 四 五 六]
    weekday = weekdays[date.wday]
    "#{date.month}月#{date.day}日 (週#{weekday}) #{time}"
  end

  # 檢查指定日期是否有任何可預訂的時段 (用於 availability_status)
  def has_any_availability_on_date?(date)
    # 使用預設人數2人來檢查
    party_size = 2
    adults = 2
    children = 0
    
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

  # 獲取按餐期分類的可用時間槽
  def get_available_slots_by_period(date, party_size, adults, children)
    slots = []
    
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
      
      availability = allocator.check_availability
      
      if availability[:has_availability]
        # 獲取餐期資訊
        business_period = @restaurant.business_periods.find(time_option[:business_period_id])
        
        slots << {
          time: time_option[:time],
          period_id: time_option[:business_period_id],
          period_name: business_period.name,
          available: true
        }
      end
    end
    
    slots
  end

  def check_reservation_enabled
    reservation_policy = @restaurant.reservation_policy
    
    unless reservation_policy&.accepts_online_reservations?
      respond_to do |format|
        format.html do
          if reservation_policy
            flash[:alert] = reservation_policy.reservation_disabled_message
          else
            flash[:alert] = "很抱歉，#{@restaurant.name} 目前暫停接受線上訂位。如需訂位，請直接致電餐廳洽詢。"
          end
          redirect_to restaurant_public_path(@restaurant.slug)
        end
        format.json do
          render json: { 
            error: reservation_policy&.reservation_disabled_message || "線上訂位功能暫停",
            reservation_enabled: false
          }, status: :service_unavailable
        end
      end
    end
  end
end 