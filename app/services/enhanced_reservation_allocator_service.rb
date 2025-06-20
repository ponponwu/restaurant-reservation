class EnhancedReservationAllocatorService < ReservationAllocatorService
  # 增強的分配方法，具有更強的併發控制
  def allocate_table_with_lock
    return nil if (@party_size || total_party_size) < 1
    return nil if exceeds_restaurant_capacity?

    # 生成分配令牌，用於併發控制
    allocation_token = SecureRandom.uuid
    
    ActiveRecord::Base.transaction do
      # 使用 SELECT FOR UPDATE 鎖定相關記錄
      locked_tables = lock_available_tables_for_update
      
      # 重新檢查可用性（在鎖定後）
      suitable_table = find_suitable_table_from_locked(locked_tables)
      
      if suitable_table
        # 原子性檢查和標記
        if mark_table_allocated(suitable_table, allocation_token)
          return suitable_table
        end
      end
      
      # 嘗試併桌（如果支援）
      if @restaurant.can_combine_tables?
        suitable_tables = find_combinable_tables_from_locked(locked_tables)
        if suitable_tables&.any?
          if mark_tables_allocated(suitable_tables, allocation_token)
            return suitable_tables
          end
        end
      end
      
      nil
    end
  rescue ActiveRecord::RecordNotUnique => e
    Rails.logger.warn "併發分配衝突: #{e.message}"
    nil
  rescue => e
    Rails.logger.error "桌位分配錯誤: #{e.message}"
    nil
  end

  # 檢查可用性（帶併發控制）
  def check_availability_with_lock
    ActiveRecord::Base.transaction do
      locked_tables = lock_available_tables_for_update
      
      # 檢查是否有合適的單桌
      suitable_single = find_suitable_table_from_locked(locked_tables)
      return { has_availability: true, allocation_type: :single } if suitable_single
      
      # 檢查是否可併桌
      if @restaurant.can_combine_tables?
        suitable_combination = find_combinable_tables_from_locked(locked_tables)
        return { has_availability: true, allocation_type: :combination } if suitable_combination&.any?
      end
      
      { has_availability: false, allocation_type: :none }
    end
  end

  private

  # 使用 SELECT FOR UPDATE 鎖定可用桌位
  def lock_available_tables_for_update
    reservation_datetime = @reservation&.reservation_datetime || @reservation_datetime
    
    # 獲取基本可用桌位
    base_tables = @restaurant.restaurant_tables.active.available_for_booking
    
    # 過濾桌位群組
    if @table_group_id.present?
      base_tables = base_tables.where(table_group_id: @table_group_id)
    end
    
    # 過濾兒童座位限制
    children_count = @children || @reservation&.children_count || 0
    base_tables = base_tables.where.not(table_type: 'bar') if children_count > 0
    
    # 使用 SELECT FOR UPDATE 鎖定桌位記錄
    locked_tables = base_tables.lock('FOR UPDATE').to_a
    
    # 獲取在目標時間已被預約的桌位 ID（也使用鎖定）
    reserved_table_ids = get_reserved_table_ids_with_lock(reservation_datetime)
    
    # 過濾掉已被預約的桌位
    locked_tables.reject { |table| reserved_table_ids.include?(table.id) }
  end

  # 帶鎖定的保留桌位 ID 查詢
  def get_reserved_table_ids_with_lock(datetime)
    return [] unless datetime

    if @restaurant.policy.unlimited_dining_time?
      get_reserved_table_ids_unlimited_with_lock(datetime)
    else
      get_reserved_table_ids_limited_with_lock(datetime)
    end
  end

  def get_reserved_table_ids_unlimited_with_lock(datetime)
    return [] unless @business_period_id
    
    target_date = datetime.to_date
    business_period = BusinessPeriod.find(@business_period_id)
    
    # 使用 FOR UPDATE 鎖定衝突的訂位記錄
    conflicting_reservations = Reservation.where(restaurant: @restaurant)
                                         .where(status: %w[pending confirmed])
                                         .where('DATE(reservation_datetime) = ?', target_date)
                                         .where(business_period: business_period)
                                         .lock('FOR UPDATE')
                                         .includes(:table, table_combination: :restaurant_tables)

    extract_table_ids_from_reservations(conflicting_reservations)
  end

  def get_reserved_table_ids_limited_with_lock(datetime)
    duration_minutes = @restaurant.dining_duration_with_buffer
    return [] unless duration_minutes

    start_time = datetime
    end_time = datetime + duration_minutes.minutes

    # 使用 FOR UPDATE 鎖定時間重疊的訂位記錄
    conflicting_reservations = Reservation.where(restaurant: @restaurant)
                                         .where(status: %w[pending confirmed])
                                         .where(
                                           "(reservation_datetime <= ? AND reservation_datetime + INTERVAL '#{duration_minutes} minutes' > ?) OR " +
                                           "(reservation_datetime < ? AND reservation_datetime + INTERVAL '#{duration_minutes} minutes' >= ?)",
                                           start_time, start_time,
                                           end_time, end_time
                                         )
                                         .lock('FOR UPDATE')
                                         .includes(:table, table_combination: :restaurant_tables)

    extract_table_ids_from_reservations(conflicting_reservations)
  end

  def extract_table_ids_from_reservations(reservations)
    reserved_table_ids = []
    
    reservations.each do |reservation|
      # 單一桌位
      if reservation.table_id.present?
        reserved_table_ids << reservation.table_id
      end
      
      # 併桌桌位
      if reservation.table_combination.present?
        reserved_table_ids.concat(
          reservation.table_combination.restaurant_tables.pluck(:id)
        )
      end
    end
    
    reserved_table_ids.uniq
  end

  # 從已鎖定的桌位中尋找合適的單桌
  def find_suitable_table_from_locked(locked_tables)
    party_size = total_party_size
    suitable_tables = locked_tables.select { |table| table.suitable_for?(party_size) }
    
    return nil if suitable_tables.empty?
    
    # 智慧選擇邏輯（與原始版本相同）
    exact_match = suitable_tables.find { |table| table.capacity == party_size }
    return exact_match if exact_match
    
    larger_tables = suitable_tables.select { |table| table.capacity > party_size }
                                  .sort_by { |table| [table.capacity, table.sort_order] }
    return larger_tables.first if larger_tables.any?
    
    suitable_tables.sort_by { |table| 
      max_cap = table.max_capacity.present? ? table.max_capacity : table.capacity
      [max_cap, table.sort_order] 
    }.first
  end

  # 從已鎖定的桌位中尋找可併桌的組合
  def find_combinable_tables_from_locked(locked_tables)
    party_size = total_party_size
    
    # 按桌位群組分類
    tables_by_group = locked_tables.group_by(&:table_group_id)
    
    tables_by_group.each do |group_id, group_tables|
      # 嘗試找到能滿足人數需求的桌位組合
      combination = find_table_combination(group_tables, party_size)
      return combination if combination&.any?
    end
    
    nil
  end

  # 原子性標記桌位已分配
  def mark_table_allocated(table, allocation_token)
    # 再次檢查桌位是否仍然可用（防止 race condition）
    reservation_datetime = @reservation&.reservation_datetime || @reservation_datetime
    
    # 雙重檢查：確保沒有新的訂位在我們鎖定期間創建
    if table_still_available?(table, reservation_datetime)
      # 可以在這裡創建一個臨時標記或直接返回成功
      true
    else
      false
    end
  end

  def mark_tables_allocated(tables, allocation_token)
    reservation_datetime = @reservation&.reservation_datetime || @reservation_datetime
    
    # 檢查所有桌位是否仍然可用
    tables.all? { |table| table_still_available?(table, reservation_datetime) }
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
    return true unless @business_period_id
    
    target_date = datetime.to_date
    business_period = BusinessPeriod.find(@business_period_id)
    
    # 最終檢查：是否有新的訂位
    !Reservation.where(restaurant: @restaurant)
                .where(status: %w[pending confirmed])
                .where('DATE(reservation_datetime) = ?', target_date)
                .where(business_period: business_period)
                .where(
                  '(table_id = ?) OR (id IN (SELECT reservation_id FROM table_combinations tc JOIN table_combination_tables tct ON tc.id = tct.table_combination_id WHERE tct.restaurant_table_id = ?))',
                  table.id, table.id
                )
                .exists?
  end

  def check_table_available_limited(table, datetime)
    duration_minutes = @restaurant.dining_duration_with_buffer
    return true unless duration_minutes

    start_time = datetime
    end_time = datetime + duration_minutes.minutes

    # 最終檢查：是否有時間重疊的新訂位
    !Reservation.where(restaurant: @restaurant)
                .where(status: %w[pending confirmed])
                .where(
                  "(reservation_datetime <= ? AND reservation_datetime + INTERVAL '#{duration_minutes} minutes' > ?) OR " +
                  "(reservation_datetime < ? AND reservation_datetime + INTERVAL '#{duration_minutes} minutes' >= ?)",
                  start_time, start_time,
                  end_time, end_time
                )
                .where(
                  '(table_id = ?) OR (id IN (SELECT reservation_id FROM table_combinations tc JOIN table_combination_tables tct ON tc.id = tct.table_combination_id WHERE tct.restaurant_table_id = ?))',
                  table.id, table.id
                )
                .exists?
  end

  # 尋找桌位組合的演算法
  def find_table_combination(tables, target_capacity)
    # 簡化版本：嘗試兩桌併桌
    tables.combination(2).each do |table_pair|
      total_capacity = table_pair.sum(&:capacity)
      if total_capacity >= target_capacity
        return table_pair
      end
    end
    
    # 如果兩桌不夠，嘗試三桌（較少見）
    tables.combination(3).each do |table_trio|
      total_capacity = table_trio.sum(&:capacity)
      if total_capacity >= target_capacity
        return table_trio
      end
    end
    
    nil
  end
end