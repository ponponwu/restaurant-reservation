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
    # 檢查人數參數
    party_size = params[:party_size]&.to_i || 2
    
    # 檢查餐廳是否有足夠容量的桌位
    has_capacity = @restaurant.has_capacity_for_party_size?(party_size)
    
    # 縮短快取時間來減少 race condition（快取2分鐘）
    cache_key = "availability_status:#{@restaurant.id}:#{Date.current}:#{party_size}:v3"
    
    result = Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
      # 獲取接下來30天內預訂已滿的日期（減少檢查範圍）
      unavailable_dates = []
      start_date = Date.current
      end_date = 30.days.from_now  # 從90天減少到30天
      
      # 一次性預載入所有需要的資料，避免 N+1 查詢
      date_range = (start_date..end_date).to_a
      
      # 預載入所有相關的訂位資料
      all_reservations = @restaurant.reservations
                                   .where(status: %w[pending confirmed])
                                   .where('DATE(reservation_datetime) BETWEEN ? AND ?', start_date, end_date)
                                   .includes(:business_period, :table, table_combination: :restaurant_tables)
                                   .to_a
      
      # 按日期分組訂位資料
      reservations_by_date = all_reservations.group_by { |r| r.reservation_datetime.to_date }
      
      # 預載入餐廳桌位資料
      restaurant_tables = @restaurant.restaurant_tables.active.available_for_booking
                                    .includes(:table_group)
                                    .to_a
      
      # 預載入營業時段資料
      business_periods = @restaurant.business_periods.active.to_a
      business_periods_cache = business_periods.index_by(&:id)
      
      # 預載入休息日資料
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
        next if closed_dates_cache.include?(date)
        
        # 使用預載入的資料檢查可用性
        unless has_availability_on_date_optimized?(
          date, 
          reservations_by_date[date] || [], 
          restaurant_tables, 
          business_periods_cache
        )
          unavailable_dates << date.to_s
        end
      end
      
      # 計算客滿到什麼時候
      fully_booked_until = nil
      if unavailable_dates.any?
        # 檢查是否在最大預訂天數內都客滿
        max_advance_days = @restaurant.reservation_policy&.advance_booking_days || 30
        max_booking_date = Date.current + max_advance_days.days
        
        # 如果在最大預訂天數內的所有營業日都客滿，則顯示額滿訊息
        all_business_days_in_range = []
        (Date.current + 1.day..max_booking_date).each do |date|
          next if closed_dates_cache.include?(date)
          next unless business_periods_cache.values.any? { |bp| bp.operates_on_weekday?(date.wday) }
          all_business_days_in_range << date.to_s
        end
        
        # 如果所有營業日都在不可用日期列表中，則設定客滿到最大預訂日期
        if all_business_days_in_range.all? { |date| unavailable_dates.include?(date) }
          fully_booked_until = max_booking_date.to_s
        end
      end
      
      # 只有在餐廳有足夠容量時才檢查可用性
      if has_capacity
        {
          unavailable_dates: unavailable_dates,
          fully_booked_until: fully_booked_until
        }
      else
        {
          unavailable_dates: [],
          fully_booked_until: nil
        }
      end
    end
    
    # 添加容量資訊到結果中
    result[:has_capacity] = has_capacity
    
    render json: result
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
    
    # 使用餐廳的人數限制
    policy = @restaurant.reservation_policy
    min_party_size = policy&.min_party_size || 1
    max_party_size = policy&.max_party_size || @restaurant.calculate_total_capacity
    
    if party_size <= 0 || party_size < min_party_size
      render json: { error: "人數必須至少 #{min_party_size} 人" }, status: :bad_request
      return
    end
    
    if party_size > max_party_size
      render json: { error: "人數不能超過 #{max_party_size} 人" }, status: :bad_request
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

    # 使用快取來提高效能（快取5分鐘）
    cache_key = "available_slots:#{@restaurant.id}:#{date}:#{party_size}:#{adult_count}:#{child_count}"
    
    slots = Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      get_available_slots_by_period(date, party_size, adult_count, child_count)
    end
    
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
    
    # 設定訂位時間 - 使用台北時區
    @reservation.reservation_datetime = Time.zone.parse("#{@selected_date} #{params[:time_slot]}")
    @reservation.status = :confirmed  # 直接設為已確認狀態
    @reservation.business_period_id = @business_period_id
    
    # 檢查手機號碼訂位限制
    customer_phone = @reservation.customer_phone
    if customer_phone.present? && reservation_policy.phone_booking_limit_exceeded?(customer_phone)
      @reservation.errors.add(:customer_phone, "訂位次數已達上限。")
      @selected_date = Date.parse(params[:date]) rescue Date.current
      render :new, status: :unprocessable_entity
      return
    end

    # 使用事務處理確保桌位分配的原子性
    begin
      ReservationLockService.with_lock(@restaurant.id, @reservation.reservation_datetime, @reservation.party_size) do
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
          
          # 在分配桌位前再次檢查可用性（防止 race condition）
          availability_check = allocator.check_availability
          unless availability_check[:has_availability]
            @reservation.errors.add(:base, '該時段已無可用桌位，請選擇其他時間。')
            @selected_date = Date.parse(params[:date]) rescue Date.current
            render :new, status: :unprocessable_entity
            return
          end
          
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
      end
    rescue ConcurrentReservationError => e
      @reservation.errors.add(:base, e.message)
      @selected_date = Date.parse(params[:date]) rescue Date.current
      render :new, status: :unprocessable_entity
      return
    rescue => e
      Rails.logger.error "Reservation allocation error: #{e.message}\n#{e.backtrace.join("\n")}"
      @reservation.errors.add(:base, '訂位處理時發生錯誤，請稍後再試。')
      @selected_date = Date.parse(params[:date]) rescue Date.current
      render :new, status: :unprocessable_entity
      return
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
    @restaurant = Restaurant.includes(
      :reservation_policy,
      :business_periods,
      :closure_dates,
      restaurant_tables: :table_group
    ).find_by!(slug: params[:slug])
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

  # 檢查指定日期是否有任何可預訂的時段 (用於 availability_status) - 優化版本
  def has_any_availability_on_date?(date)
    # 使用預設人數2人來檢查
    party_size = 2
    adults = 2
    children = 0
    
    # 使用餐廳的動態時間產生方法
    available_time_options = @restaurant.available_time_options_for_date(date)
    return false if available_time_options.empty?
    
    # 預載入當天所有相關的訂位資料
    existing_reservations = @restaurant.reservations
                                      .where(status: %w[pending confirmed])
                                      .where('DATE(reservation_datetime) = ?', date)
                                      .includes(:table, :business_period, table_combination: :restaurant_tables)
    
    # 預載入餐廳桌位資料
    restaurant_tables = @restaurant.restaurant_tables.active.available_for_booking
                                  .includes(:table_group)
    
    # 按餐期分組現有訂位（避免 N+1 查詢）
    reservations_by_period = existing_reservations.to_a.group_by(&:business_period_id)
    
    # 檢查是否有任何時段可用
    available_time_options.each do |time_option|
      business_period_id = time_option[:business_period_id]
      datetime = time_option[:datetime]
      
      # 檢查該時段是否有可用桌位
      if has_availability_for_slot?(
        restaurant_tables, 
        reservations_by_period[business_period_id] || [], 
        datetime, 
        party_size, 
        business_period_id
      )
        return true
      end
    end
    
    false
  end

  # 優化版本的可用性檢查（用於批量處理）
  def has_availability_on_date_optimized?(date, day_reservations, restaurant_tables, business_periods_cache)
    party_size = 2  # 使用預設人數2人來檢查
    
    # 使用餐廳的動態時間產生方法
    available_time_options = @restaurant.available_time_options_for_date(date)
    return false if available_time_options.empty?
    
    # 按餐期分組當天的訂位資料
    reservations_by_period = day_reservations.group_by(&:business_period_id)
    
    # 檢查是否有任何時段可用
    available_time_options.each do |time_option|
      business_period_id = time_option[:business_period_id]
      datetime = time_option[:datetime]
      
      # 檢查該時段是否有可用桌位
      if has_availability_for_slot_optimized?(
        restaurant_tables, 
        reservations_by_period[business_period_id] || [], 
        datetime, 
        party_size, 
        business_period_id
      )
        return true
      end
    end
    
    false
  end

  # 優化版本的時段可用性檢查
  def has_availability_for_slot_optimized?(restaurant_tables, period_reservations, datetime, party_size, business_period_id)
    # 獲取該時段已被預訂的桌位 ID
    reserved_table_ids = get_reserved_table_ids_for_period_optimized(period_reservations, datetime, business_period_id)
    
    # 過濾掉已被預訂的桌位
    available_tables = restaurant_tables.reject { |table| reserved_table_ids.include?(table.id) }
    
    # 檢查是否有適合的單一桌位
    suitable_table = available_tables.find { |table| table.suitable_for?(party_size) }
    return true if suitable_table
    
    # 檢查是否可以併桌
    if @restaurant.can_combine_tables?
      combinable_tables = available_tables.select { |table| table.can_combine? }
      return has_combinable_tables_for_party?(combinable_tables, party_size)
    end
    
    false
  end

  # 優化版本的已預訂桌位 ID 獲取
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

  # 優化版本的時間衝突檢查
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

  # 獲取按餐期分類的可用時間槽（優化版本）
  def get_available_slots_by_period(date, party_size, adults, children)
    slots = []
    
    # 一次性載入所有需要的資料，避免 N+1 查詢
    available_time_options = @restaurant.available_time_options_for_date(date)
    return slots if available_time_options.empty?
    
    # 預載入營業時段資料
    business_period_ids = available_time_options.map { |option| option[:business_period_id] }.uniq
    business_periods_cache = @restaurant.business_periods.where(id: business_period_ids)
                                       .index_by(&:id)
    
    # 預載入當天所有相關的訂位資料，避免在迴圈中重複查詢
    target_date = date
    existing_reservations = @restaurant.reservations
                                      .where(status: %w[pending confirmed])
                                      .where('DATE(reservation_datetime) = ?', target_date)
                                      .includes(:table, :business_period, table_combination: :restaurant_tables)
    
    # 預載入餐廳桌位資料
    restaurant_tables = @restaurant.restaurant_tables.active.available_for_booking
                                  .includes(:table_group)
    
    # 按餐期分組現有訂位（避免 N+1 查詢）
    reservations_by_period = existing_reservations.to_a.group_by(&:business_period_id)
    
    # 過濾有兒童的情況下排除吧台座位
    if children > 0
      restaurant_tables = restaurant_tables.where.not(table_type: 'bar')
    end
    
    # 批量檢查可用性
    available_time_options.each do |time_option|
      business_period_id = time_option[:business_period_id]
      datetime = time_option[:datetime]
      
      # 使用快取的營業時段資料
      business_period = business_periods_cache[business_period_id]
      next unless business_period
      
      # 檢查該時段是否有可用桌位
      if has_availability_for_slot?(
        restaurant_tables, 
        reservations_by_period[business_period_id] || [], 
        datetime, 
        party_size, 
        business_period_id
      )
        slots << {
          time: time_option[:time],
          period_id: business_period_id,
          period_name: business_period.name,
          available: true
        }
      end
    end
    
    slots
  end

  # 檢查特定時段是否有可用桌位（優化版本）
  def has_availability_for_slot?(restaurant_tables, period_reservations, datetime, party_size, business_period_id)
    # 獲取該時段已被預訂的桌位 ID
    reserved_table_ids = get_reserved_table_ids_for_period(period_reservations, datetime, business_period_id)
    
    # 過濾掉已被預訂的桌位
    available_tables = restaurant_tables.reject { |table| reserved_table_ids.include?(table.id) }
    
    # 檢查是否有適合的單一桌位
    suitable_table = available_tables.find { |table| table.suitable_for?(party_size) }
    return true if suitable_table
    
    # 檢查是否可以併桌
    if @restaurant.can_combine_tables?
      combinable_tables = available_tables.select { |table| table.can_combine? }
      return has_combinable_tables_for_party?(combinable_tables, party_size)
    end
    
    false
  end

  # 獲取特定餐期已被預訂的桌位 ID（優化版本）
  def get_reserved_table_ids_for_period(period_reservations, datetime, business_period_id)
    reserved_table_ids = []
    
    period_reservations.each do |reservation|
      # 檢查時間衝突
      if has_time_conflict?(reservation, datetime, business_period_id)
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

  # 檢查時間衝突（優化版本）
  def has_time_conflict?(reservation, target_datetime, target_business_period_id)
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

  # 檢查是否有可併桌的組合（優化版本）
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

  # 檢查是否能組成適合的併桌組合（優化版本）
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