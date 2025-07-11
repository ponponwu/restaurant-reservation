class RestaurantAvailabilityService
  def initialize(restaurant)
    @restaurant = restaurant
    @reservations_cache = {}
    @table_combinations_loaded = false
  end

  # 獲取可預約日期
  def get_available_dates(party_size, _adults = nil, _children = nil)
    start_date = Date.current
    advance_booking_days = @restaurant.reservation_policy&.advance_booking_days || 30
    end_date = start_date + advance_booking_days.days

    available_dates = []
    availability_service = AvailabilityService.new(@restaurant)

    # 使用快取避免重複查詢
    all_reservations = cached_reservations_for_date_range(start_date, end_date)

    # 預載入餐廳桌位資料
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

  # 獲取可預約時段
  def get_available_times(date, party_size, _adults = nil, _children = nil)
    available_times = []
    target_date = date.is_a?(Date) ? date : Date.parse(date.to_s)

    # 使用餐廳的動態時間產生方法
    available_time_options = @restaurant.available_time_options_for_date(target_date)

    # 在迴圈外初始化，避免重複建立和查詢
    availability_service = AvailabilityService.new(@restaurant)

    # 使用快取避免重複查詢
    day_reservations = cached_reservations_for_date(target_date)

    # 預載入餐廳桌位資料
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

    available_times
  end

  # 計算額滿日期
  def calculate_full_booked_until(party_size, _adults = nil, _children = nil)
    start_date = Date.current
    advance_booking_days = @restaurant.reservation_policy&.advance_booking_days || 30
    end_date = start_date + advance_booking_days.days

    # 在迴圈外初始化，避免重複建立和查詢
    availability_service = AvailabilityService.new(@restaurant)

    # 使用快取避免重複查詢
    all_reservations = cached_reservations_for_date_range(start_date, end_date)

    # 預載入餐廳桌位資料
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
        return date
      end
    end

    # 如果可預約天數內都沒有空位，回傳最後一天
    end_date
  end

  # 檢查特定日期是否有可用性
  def has_availability_on_date?(date, party_size, _adults = nil, _children = nil)
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

  # 獲取不可用日期（優化版本）
  def get_unavailable_dates_optimized(party_size, max_days)
    # 使用 AvailabilityService 處理
    availability_service = AvailabilityService.new(@restaurant)
    availability_service.get_unavailable_dates_optimized(party_size, max_days)
  end

  private

  # 快取查詢結果以避免重複資料庫查詢
  def cached_reservations_for_date_range(start_date, end_date)
    cache_key = "#{start_date}_#{end_date}"

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
      # 只檢查範圍快取（包含 '_' 的key）
      next unless cache_key.include?('_')

      parts = cache_key.split('_')
      next unless parts.length == 2 && parts.all?(&:present?)

      start_date_str, end_date_str = parts
      begin
        start_date = Date.parse(start_date_str)
        end_date = Date.parse(end_date_str)

        if date >= start_date && date <= end_date
          return reservations.select { |r| r.reservation_datetime.to_date == date }
        end
      rescue ArgumentError
        # 跳過無效的日期格式
        next
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
end
