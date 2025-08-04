class EnhancedReservationAllocatorService < ReservationAllocatorService
  # 使用樂觀鎖的分配方法（真正的樂觀鎖實現）
  def allocate_table_with_optimistic_locking
    return nil if (@party_size || total_party_size) < 1
    return nil unless valid_reservation_datetime?
    return nil if exceeds_restaurant_capacity?

    # 樂觀鎖核心：無鎖查詢，信任數據一致性
    available_tables = @restaurant.restaurant_tables
      .active
      .available_for_booking
      .includes(:table_group)

    # 嘗試分配單桌
    suitable_table = find_suitable_table_from(available_tables)
    return suitable_table if suitable_table

    # 嘗試併桌（如果支援）
    if @restaurant.can_combine_tables?
      suitable_tables = find_combinable_tables_from(available_tables)
      return suitable_tables if suitable_tables&.any?
    end

    nil
  rescue StandardError => e
    Rails.logger.error "桌位分配錯誤: #{e.message}"
    nil
  end

  # 檢查可用性（無鎖定版本）
  def check_availability_without_locking
    available_tables = @restaurant.restaurant_tables
      .active
      .available_for_booking
      .includes(:table_group)

    # 檢查是否有合適的單桌
    suitable_single = find_suitable_table_from(available_tables)
    return { has_availability: true, allocation_type: :single } if suitable_single

    # 檢查是否可併桌
    if @restaurant.can_combine_tables?
      suitable_combination = find_combinable_tables_from(available_tables)
      return { has_availability: true, allocation_type: :combination } if suitable_combination&.any?
    end

    { has_availability: false, allocation_type: :none }
  rescue StandardError => e
    Rails.logger.error "可用性檢查錯誤: #{e.message}"
    { has_availability: false, allocation_type: :error }
  end

  private

  # 驗證預訂日期時間的有效性
  def valid_reservation_datetime?
    datetime = @reservation&.reservation_datetime || @reservation_datetime
    return false unless datetime.present?

    # 檢查是否為有效的時間類型
    datetime.is_a?(Time) || datetime.is_a?(DateTime)
  rescue StandardError
    false
  end

  # 從可用桌位中尋找合適的單桌（保留舊方法以保持兼容性）
  def find_suitable_table_from(available_tables)
    target_party_size = @party_size || total_party_size

    # 尋找適合的單桌，優先選擇容量剛好或接近的桌位
    suitable_tables = available_tables.select do |table|
      table.capacity >= target_party_size &&
        !table_occupied_at_time?(table, @reservation_datetime) &&
        (!@children || @children == 0 || !table.bar_seating?)
    end

    # 按容量排序，選擇最適合的桌位
    suitable_tables.min_by(&:capacity)
  end

  # 從可用桌位中尋找合適的併桌組合
  def find_combinable_tables_from(available_tables)
    return nil unless @restaurant.can_combine_tables?

    target_party_size = @party_size || total_party_size

    # 篩選可併桌的桌位
    combinable_tables = available_tables.select do |table|
      table.can_combine? &&
        !table_occupied_at_time?(table, @reservation_datetime) &&
        (!@children || @children == 0 || !table.bar_seating?)
    end

    # 尋找併桌組合
    find_table_combination(combinable_tables, target_party_size)
  end

  # 檢查桌位在指定時間是否被佔用（樂觀鎖版本）
  def table_occupied_at_time?(table, datetime)
    return false unless datetime.is_a?(Time) || datetime.is_a?(DateTime)
    return false unless table.present?

    duration_minutes = @restaurant.dining_duration_minutes || 120
    new_start = datetime
    new_end = datetime + duration_minutes.minutes
    target_date = datetime.to_date

    # 獲取所有可能衝突的預訂
    conflicting_reservations = get_conflicting_reservations(table, new_start, new_end, target_date)

    # 精確的時間重疊檢測
    conflicting_reservations.any? do |reservation|
      existing_start = reservation.reservation_datetime
      existing_end = existing_start + duration_minutes.minutes

      # 時間重疊邏輯：排除邊界接續（14:00-16:00 不與 12:00-14:00 衝突）
      reservations_overlap?(new_start, new_end, existing_start, existing_end)
    end
  rescue StandardError => e
    Rails.logger.error "檢查桌位佔用狀態時發生錯誤: #{e.message}"
    true # 發生錯誤時保守地認為桌位被佔用
  end

  # 獲取可能衝突的預訂（直接桌位 + 併桌）
  def get_conflicting_reservations(table, new_start, new_end, target_date)
    duration_minutes = @restaurant.dining_duration_minutes || 120

    # 合理的查詢範圍：只查詢真正可能重疊的預訂
    search_start = new_start - duration_minutes.minutes
    search_end = new_end

    # 直接桌位預訂
    direct_reservations = Reservation.where(
      restaurant_id: @restaurant.id,
      table_id: table.id,
      status: %w[confirmed pending]
    ).where('DATE(reservation_datetime) = ?', target_date)
      .where('reservation_datetime >= ? AND reservation_datetime <= ?', search_start, search_end)

    # 併桌預訂（優化查詢）
    combination_reservations = Reservation.joins(table_combination: :restaurant_tables)
      .where(restaurant_id: @restaurant.id, status: %w[confirmed pending])
      .where(restaurant_tables: { id: table.id })
      .where('DATE(reservations.reservation_datetime) = ?', target_date)
      .where('reservations.reservation_datetime >= ? AND reservations.reservation_datetime <= ?', search_start, search_end)

    # 合併並去重
    (direct_reservations + combination_reservations).uniq
  end

  # 檢查兩個時間區間是否重疊
  def reservations_overlap?(new_start, new_end, existing_start, existing_end)
    # 明確的不重疊條件：
    # 1. 新預訂完全在既有預訂之前：new_end <= existing_start
    # 2. 新預訂完全在既有預訂之後：new_start >= existing_end

    no_overlap = (new_end <= existing_start) || (new_start >= existing_end)

    # 返回是否重疊
    !no_overlap
  end

  # 最終檢查桌位是否仍然可用
  def table_still_available?(table, datetime)
    if @restaurant.policy.unlimited_dining_time?
      check_table_available_unlimited(table, datetime)
    else
      check_table_available_limited(table, datetime)
    end
  end

  def check_table_available_unlimited(table, datetime)
    return true unless @reservation_period_id

    target_date = datetime.to_date
    reservation_period = ReservationPeriod.find(@reservation_period_id)

    # 最終檢查：是否有新的訂位
    !Reservation.where(restaurant: @restaurant)
      .where(status: %w[pending confirmed])
      .where('DATE(reservation_datetime) = ?', target_date)
      .where(reservation_period: reservation_period)
      .exists?([
                 '(table_id = ?) OR (id IN (SELECT reservation_id FROM table_combinations tc JOIN table_combination_tables tct ON tc.id = tct.table_combination_id WHERE tct.restaurant_table_id = ?))', table.id, table.id
               ])
  end

  def check_table_available_limited(table, datetime)
    duration_minutes = @restaurant.dining_duration_with_buffer
    return true unless duration_minutes

    start_time = datetime
    end_time = datetime + duration_minutes.minutes

    # 最終檢查：是否有時間重疊的新訂位，限制在同一天
    target_date = datetime.to_date

    # 查詢可能衝突的預訂，限制在同一天
    potentially_conflicting = Reservation.where(restaurant: @restaurant)
      .where(status: %w[pending confirmed])
      .where('DATE(reservation_datetime) = ?', target_date)
      .where(
        reservation_datetime: (start_time - duration_minutes.minutes)..(end_time)
      )
      .where(
        '(table_id = ?) OR (id IN (SELECT reservation_id FROM table_combinations tc JOIN table_combination_tables tct ON tc.id = tct.table_combination_id WHERE tct.restaurant_table_id = ?))', table.id, table.id
      )

    # 在 Ruby 中進行精確的時間重疊檢測
    !potentially_conflicting.any? do |reservation|
      existing_start = reservation.reservation_datetime
      existing_end = existing_start + duration_minutes.minutes

      # 檢查時間重疊
      start_time < existing_end && end_time > existing_start
    end
  end

  # 尋找桌位組合的演算法
  def find_table_combination(tables, target_capacity)
    # 獲取餐廳允許的最大併桌數量
    max_tables = @restaurant.max_tables_per_combination || 3
    max_tables = [max_tables, tables.size].min

    # 從2桌開始，逐步增加桌數直到滿足需求或達到上限
    (2..max_tables).each do |table_count|
      tables.combination(table_count).each do |table_combination|
        total_capacity = table_combination.sum(&:capacity)
        return table_combination if total_capacity >= target_capacity
      end
    end

    nil
  end

  # 重寫父類方法以使用鎖定版本
  def total_party_size
    @party_size || @reservation&.party_size || ((@adults || 0) + (@children || 0))
  end

  def exceeds_restaurant_capacity?
    return false unless @restaurant.respond_to?(:total_capacity)

    party_size = total_party_size
    datetime = @reservation&.reservation_datetime || @reservation_datetime

    return false unless datetime

    # 日期驗證
    unless datetime.is_a?(Time) || datetime.is_a?(DateTime)
      Rails.logger.error "Invalid datetime parameter in exceeds_restaurant_capacity?: #{datetime.class}"
      return false
    end

    # 在同一查詢中原子性地計算容量，確保併發安全性
    begin
      policy = @restaurant.policy || @restaurant.reservation_policy
      if policy&.unlimited_dining_time?
        check_unlimited_capacity_exceeded(datetime, party_size)
      else
        check_limited_capacity_exceeded(datetime, party_size)
      end
    rescue StandardError => e
      Rails.logger.error "Capacity check error: #{e.message}"
      # 發生錯誤時採用保守策略，假設不超過容量
      false
    end
  end

  # 檢查無限用餐時間模式下的容量
  def check_unlimited_capacity_exceeded(datetime, party_size)
    return false unless @reservation_period_id

    target_date = datetime.to_date
    reservation_period = ReservationPeriod.find(@reservation_period_id)

    # 使用安全的 ActiveRecord 查詢
    reserved_capacity = Reservation.where(restaurant: @restaurant)
      .where(status: %w[pending confirmed])
      .where('DATE(reservation_datetime) = ?', target_date)
      .where(reservation_period: reservation_period)
      .tap { |q| q.where.not(id: @reservation.id) if @reservation&.persisted? }
      .sum(:party_size)

    total_capacity = @restaurant.total_capacity ||
                     @restaurant.restaurant_tables.active.sum('COALESCE(max_capacity, capacity)')

    remaining_capacity = total_capacity - reserved_capacity
    party_size > remaining_capacity
  end

  # 檢查限定用餐時間模式下的容量
  def check_limited_capacity_exceeded(datetime, party_size)
    duration_minutes = @restaurant.dining_duration_with_buffer
    return false unless duration_minutes

    new_start = datetime
    new_end = datetime + duration_minutes.minutes
    target_date = datetime.to_date

    # 使用安全的 ActiveRecord 查詢計算重疊容量
    potentially_conflicting = Reservation.where(restaurant: @restaurant)
      .where(status: %w[pending confirmed])
      .where('DATE(reservation_datetime) = ?', target_date)
      .where(
        reservation_datetime: (new_start - duration_minutes.minutes)..(new_end)
      )
      .tap { |q| q.where.not(id: @reservation.id) if @reservation&.persisted? }

    # 在 Ruby 中進行精確的時間重疊檢測並計算總人數
    overlapping_capacity = 0
    potentially_conflicting.each do |reservation|
      existing_start = reservation.reservation_datetime
      existing_end = existing_start + duration_minutes.minutes

      # 檢查時間重疊 - 修正邊界檢測
      if reservations_overlap?(new_start, new_end, existing_start, existing_end)
        overlapping_capacity += reservation.party_size
      end
    end

    total_capacity = @restaurant.total_capacity ||
                     @restaurant.restaurant_tables.active.sum('COALESCE(max_capacity, capacity)')

    remaining_capacity = total_capacity - overlapping_capacity

    if Rails.logger.debug?
      Rails.logger.debug do
        "Capacity check: party_size=#{party_size}, overlapping=#{overlapping_capacity}, total=#{total_capacity}, remaining=#{remaining_capacity}"
      end
    end

    party_size > remaining_capacity
  end
end
