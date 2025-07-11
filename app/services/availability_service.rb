# 可用性檢查服務 - 整合重複的可用性檢查邏輯
class AvailabilityService
  def initialize(restaurant)
    @restaurant = restaurant
    @reserved_table_ids_cache = {}
  end

  # 檢查指定日期是否有任何可預訂的時段
  def has_any_availability_on_date?(date, party_size = 2)
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

  # 獲取按餐期分類的可用時間槽
  def get_available_slots_by_period(date, party_size, _adults, children)
    slots = []

    # 一次性載入所有需要的資料，避免 N+1 查詢
    available_time_options = @restaurant.available_time_options_for_date(date)
    return slots if available_time_options.empty?

    # 預載入營業時段資料
    business_period_ids = available_time_options.pluck(:business_period_id).compact.uniq
    business_periods_cache = @restaurant.business_periods.where(id: business_period_ids)
      .index_by(&:id)

    # 預載入當天所有相關的訂位資料，避免在迴圈中重複查詢
    existing_reservations = @restaurant.reservations
      .where(status: %w[pending confirmed])
      .where('DATE(reservation_datetime) = ?', date)
      .includes(:table, :business_period, table_combination: :restaurant_tables)

    # 預載入餐廳桌位資料
    restaurant_tables = @restaurant.restaurant_tables.active.available_for_booking
      .includes(:table_group)

    # 按餐期分組現有訂位（避免 N+1 查詢）
    reservations_by_period = existing_reservations.to_a.group_by(&:business_period_id)

    # 過濾有兒童的情況下排除吧台座位
    restaurant_tables = restaurant_tables.where.not(table_type: 'bar') if children.positive?

    # 批量檢查可用性
    available_time_options.each do |time_option|
      business_period_id = time_option[:business_period_id]
      datetime = time_option[:datetime]
      is_special_date = business_period_id.nil?

      # 如果是常規日，但找不到對應的餐期，則跳過
      business_period = business_periods_cache[business_period_id] unless is_special_date
      next if !is_special_date && !business_period

      # 檢查該時段是否有可用桌位
      # 對於特殊日，reservations_by_period[nil] 會回傳對應的訂位
      next unless has_availability_for_slot?(
        restaurant_tables,
        reservations_by_period[business_period_id] || [],
        datetime,
        party_size,
        business_period_id
      )

      slots << {
        time: time_option[:time],
        period_id: business_period_id,
        period_name: is_special_date ? '特別營業時段' : business_period.name,
        available: true
      }
    end

    slots
  end

  # 批量檢查多個日期的可用性（用於 availability_status）
  def check_availability_for_date_range(start_date, end_date, party_size = 2)
    unavailable_dates = []

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

    # 建立統一的休息日快取 (同時檢查兩套系統)
    closed_dates_cache = build_unified_closed_dates_cache(date_range)

    # 批量檢查每天的可用性
    date_range.each do |date|
      next if closed_dates_cache.include?(date)

      # 使用預載入的資料檢查可用性
      next if has_availability_on_date_optimized?(
        date,
        reservations_by_date[date] || [],
        restaurant_tables,
        business_periods_cache,
        party_size
      )

      unavailable_dates << date.to_s
    end

    unavailable_dates
  end

  # 獲取不可用日期（優化版本）
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

    # 建立統一的休息日快取 (同時檢查兩套系統)
    closed_dates_cache = build_unified_closed_dates_cache(date_range)
    
    # 預載入特殊日期設定
    special_dates_cache = @restaurant.special_reservation_dates.active
                                     .where('start_date <= ? AND end_date >= ?', end_date, start_date)
                                     .group_by { |sd| (sd.start_date..sd.end_date).to_a }.transform_values(&:first)
                                     .flat_map { |k, v| k.map { |date| [date, v] } }.to_h


    # 批量檢查每天的可用性
    date_range.each do |date|
      # 跳過公休日
      next if closed_dates_cache.include?(date)
      
      special_date = special_dates_cache[date]

      # 如果不是特殊營業日，且沒有常規營業時段，則跳過
      if special_date.nil? || !special_date.custom_hours?
        next unless business_periods_cache.values.any? { |bp| bp.operates_on_weekday?(date.wday) }
      end

      # 檢查當天是否有任何時段可以容納該人數
      next if has_availability_on_date_cached?(
        date,
        reservations_by_date[date] || [],
        restaurant_tables,
        business_periods_cache,
        party_size
      )

      unavailable_dates << date.to_s
    end

    unavailable_dates
  end

  # 檢查特定日期是否有可用性（使用快取）
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

      # 處理特殊訂位日（business_period_id 為 nil）
      if business_period_id.nil?
        # 特殊訂位日不需要檢查營業時段，直接檢查桌位可用性
        has_availability_for_slot_optimized?(
          restaurant_tables,
          reservations_by_period[business_period_id] || [],
          datetime,
          party_size,
          business_period_id
        )
      else
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
  end

  # 檢查特定時段是否有可用性（優化版本）
  def has_availability_for_slot_optimized?(restaurant_tables, period_reservations, datetime, party_size,
                                           business_period_id)
    # 快取已計算的預訂桌位 ID，避免重複計算
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
      combinable_tables = available_tables.select(&:can_combine?)
      return has_combinable_tables_for_party?(combinable_tables, party_size)
    end

    false
  end

  # 獲取特定時段已預訂的桌位 ID（優化版本）
  def get_reserved_table_ids_for_period_optimized(period_reservations, datetime, business_period_id)
    reserved_table_ids = []

    # 先篩選出有時間衝突的 reservations
    conflicting_reservations = period_reservations.select do |reservation|
      has_time_conflict_optimized?(reservation, datetime, business_period_id)
    end

    # 收集直接預訂的桌位
    conflicting_reservations.each do |reservation|
      reserved_table_ids << reservation.table_id if reservation.table_id
    end

    # 批次處理 table_combinations：只查詢有衝突的 reservations
    conflicting_reservation_ids = conflicting_reservations.map(&:id)
    if conflicting_reservation_ids.any?
      table_combinations = TableCombination
        .where(reservation_id: conflicting_reservation_ids)
        .includes(table_combination_tables: :restaurant_table)

      table_combinations.each do |table_combination|
        table_combination.restaurant_tables.each do |table|
          reserved_table_ids << table.id
        end
      end
    end

    reserved_table_ids.compact.uniq
  end

  # 檢查時間衝突（優化版本）
  def has_time_conflict_optimized?(reservation, target_datetime, target_business_period_id)
    # 特殊訂位日處理（business_period_id 為 nil）
    if target_business_period_id.nil?
      return has_time_conflict_for_special_date?(reservation, target_datetime)
    end

    # 如果是無限時模式，檢查同一餐期的衝突
    if @restaurant.unlimited_dining_time?
      return reservation.business_period_id == target_business_period_id &&
             reservation.reservation_datetime.to_date == target_datetime.to_date
    end

    # 限時模式：檢查時間重疊
    duration_minutes = @restaurant.dining_duration_with_buffer_for_date(target_datetime.to_date)
    return false unless duration_minutes

    reservation_start = reservation.reservation_datetime
    reservation_end = reservation_start + duration_minutes.minutes
    target_start = target_datetime
    target_end = target_start + duration_minutes.minutes

    # 檢查時間區間是否重疊
    !(reservation_end <= target_start || target_end <= reservation_start)
  end

  private

  # 檢查特定時段是否有可用桌位
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
      combinable_tables = available_tables.select(&:can_combine?)
      return has_combinable_tables_for_party?(combinable_tables, party_size)
    end

    false
  end

  # 獲取特定餐期已被預訂的桌位 ID
  def get_reserved_table_ids_for_period(period_reservations, datetime, business_period_id)
    reserved_table_ids = []

    # 先篩選出有時間衝突的 reservations
    conflicting_reservations = period_reservations.select do |reservation|
      has_time_conflict?(reservation, datetime, business_period_id)
    end

    # 收集直接預訂的桌位
    conflicting_reservations.each do |reservation|
      reserved_table_ids << reservation.table_id if reservation.table_id
    end

    # 批次處理 table_combinations：只查詢有衝突的 reservations
    conflicting_reservation_ids = conflicting_reservations.map(&:id)
    if conflicting_reservation_ids.any?
      table_combinations = TableCombination
        .where(reservation_id: conflicting_reservation_ids)
        .includes(table_combination_tables: :restaurant_table)

      table_combinations.each do |table_combination|
        table_combination.restaurant_tables.each do |table|
          reserved_table_ids << table.id
        end
      end
    end

    reserved_table_ids.compact.uniq
  end

  # 檢查時間衝突
  def has_time_conflict?(reservation, target_datetime, target_business_period_id)
    # 特殊訂位日處理（business_period_id 為 nil）
    if target_business_period_id.nil?
      return has_time_conflict_for_special_date?(reservation, target_datetime)
    end

    # 如果是無限時模式，檢查同一餐期的衝突
    if @restaurant.unlimited_dining_time?
      return reservation.business_period_id == target_business_period_id &&
             reservation.reservation_datetime.to_date == target_datetime.to_date
    end

    # 限時模式：檢查時間重疊
    duration_minutes = @restaurant.dining_duration_with_buffer_for_date(target_datetime.to_date)
    return false unless duration_minutes

    reservation_start = reservation.reservation_datetime
    reservation_end = reservation_start + duration_minutes.minutes
    target_start = target_datetime
    target_end = target_start + duration_minutes.minutes

    # 檢查時間區間是否重疊
    !(reservation_end <= target_start || target_end <= reservation_start)
  end

  # 檢查特殊訂位日的時間衝突
  def has_time_conflict_for_special_date?(reservation, target_datetime)
    target_date = target_datetime.to_date
    
    # 檢查是否為同一天的訂位
    return false unless reservation.reservation_datetime.to_date == target_date
    
    # 獲取特殊訂位日的用餐時間設定
    duration_minutes = @restaurant.dining_duration_with_buffer_for_date(target_date)
    return false unless duration_minutes
    
    reservation_start = reservation.reservation_datetime
    reservation_end = reservation_start + duration_minutes.minutes
    target_start = target_datetime
    target_end = target_start + duration_minutes.minutes

    # 檢查時間區間是否重疊
    !(reservation_end <= target_start || target_end <= reservation_start)
  end

  # 檢查是否有可併桌的組合
  def has_combinable_tables_for_party?(combinable_tables, party_size)
    return false if combinable_tables.empty?

    # 按群組分組桌位
    tables_by_group = combinable_tables.group_by(&:table_group_id)

    tables_by_group.each_value do |group_tables|
      # 檢查該群組是否能組成適合的組合
      return true if can_form_suitable_combination?(group_tables, party_size)
    end

    false
  end

  # 檢查是否能組成適合的併桌組合
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

  # 優化版本的可用性檢查（用於批量處理）
  def has_availability_on_date_optimized?(date, day_reservations, restaurant_tables, _business_periods_cache,
                                          party_size)
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

  # 建立休息日快取 (支援兩套系統)
  def build_closed_dates_cache(closure_dates, date_range)
    closed_dates_cache = Set.new

    # 處理舊的 ClosureDate 系統
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

    # 處理新的 SpecialReservationDate 系統
    special_dates = @restaurant.special_reservation_dates
                               .active
                               .where('start_date <= ? AND end_date >= ?', date_range.last, date_range.first)
                               .to_a

    special_dates.each do |special_date|
      if special_date.closed?
        # 對於公休的特殊日期，將所有覆蓋的日期加入關閉快取
        date_range.each do |date|
          closed_dates_cache.add(date) if special_date.covers_date?(date)
        end
      end
      # 注意：自訂時段的特殊日期不會加入 closed_dates_cache
      # 因為它們不是完全關閉，而是有特殊的營業時間
    end

    closed_dates_cache
  end

  # 建立統一的休息日檢查方法 (同時檢查兩套系統)
  def build_unified_closed_dates_cache(date_range)
    # 預載入舊系統的休息日資料
    closure_dates = @restaurant.closure_dates
                               .where('date BETWEEN ? AND ? OR recurring = ?', 
                                      date_range.first, date_range.last, true)
                               .to_a

    # 使用現有方法建立快取
    build_closed_dates_cache(closure_dates, date_range)
  end
end
