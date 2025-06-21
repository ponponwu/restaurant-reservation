class ReservationAllocatorService
  # 初始化時可以傳入 reservation 物件或個別參數
  def initialize(params)
    if params.is_a?(Reservation)
      @reservation = params
      @restaurant = params.restaurant
      @business_period_id = params.business_period_id
      @reservation_datetime = params.reservation_datetime
    else
      @restaurant = params[:restaurant]
      @party_size = params[:party_size] || params[:guest_count]
      @adults = params[:adults] || 0
      @children = params[:children] || params[:child_count] || 0
      @reservation_datetime = params[:reservation_datetime] ||
                              Time.zone.parse("#{params[:date]} #{params[:time]}")
      @business_period_id = params[:business_period_id]
      @table_group_id = params[:table_group_id]
    end
  end

  def allocate_table
    return nil if (@party_size || total_party_size) < 1
    return nil if exceeds_restaurant_capacity?

    # 先嘗試找單一桌位
    if (table = find_suitable_table)
      return table
    end

    # 如果找不到單一桌位，檢查是否可以併桌（僅限同群組）
    if @restaurant.can_combine_tables?
      tables = find_combinable_tables

      if tables
        # 直接返回桌位陣列，讓控制器處理併桌組合的創建
        return tables
      end
    end

    nil
  end

  def find_available_tables
    available_tables.select { |table| table.suitable_for?(total_party_size) }
  end

  def check_availability
    # 分別檢查單一桌位和併桌可用性
    suitable_table = find_single_suitable_table
    combinable_tables = find_combinable_tables

    # 有可用性的條件：有適合的單一桌位 OR 有可併桌的組合
    has_availability = suitable_table.present? || combinable_tables.present?

    {
      has_availability: has_availability,
      available_tables: find_available_tables,
      suitable_table: suitable_table,
      can_combine: can_combine_tables?,
      combinable_tables: combinable_tables || []
    }
  end

  def find_combinable_tables
    return nil unless can_combine_tables?

    party_size = total_party_size
    combinable_tables = available_tables.select { |table| can_table_combine?(table) }

    return nil if combinable_tables.empty?

    # 只在同群組內尋找組合
    tables_by_group = combinable_tables.group_by(&:table_group_id)

    tables_by_group.each_value do |group_tables|
      combination = find_best_combination_in_group(group_tables, party_size)
      return combination if combination
    end

    # 不允許跨群組併桌
    nil
  end

  # 簡化：檢查桌位在指定餐期的預訂狀況（不限時模式下每餐期每桌只有一個訂位）
  def check_table_booking_in_period(table, target_datetime)
    return { has_booking: false, existing_booking: nil } unless @business_period_id

    target_date = target_datetime.to_date
    business_period = BusinessPeriod.find(@business_period_id)

    # 查找該桌位在同一餐期的預訂
    existing_booking = Reservation.where(restaurant: @restaurant)
      .where(status: %w[pending confirmed])
      .where('DATE(reservation_datetime) = ?', target_date)
      .where(business_period: business_period)
      .where(
        '(table_id = ?) OR (id IN (SELECT reservation_id FROM table_combinations tc JOIN table_combination_tables tct ON tc.id = tct.table_combination_id WHERE tct.restaurant_table_id = ?))',
        table.id, table.id
      )
      .first

    {
      has_booking: existing_booking.present?,
      existing_booking: existing_booking
    }
  end

  private

  def total_party_size
    @party_size || @reservation&.party_size || ((@adults || 0) + (@children || 0))
  end

  def available_tables
    base_query = @restaurant.restaurant_tables.active.available_for_booking

    # 過濾已被預約的桌位
    reservation_datetime = @reservation&.reservation_datetime || @reservation_datetime
    reserved_table_ids = get_reserved_table_ids(reservation_datetime)

    base_query = base_query.where.not(id: reserved_table_ids) if reserved_table_ids.any?

    # 如果有兒童，排除吧台座位
    children_count = @children || @reservation&.children_count || 0
    base_query = base_query.where.not(table_type: 'bar') if children_count.positive?

    # 如果指定了桌位群組，只查詢該群組的桌位
    base_query = base_query.where(table_group_id: @table_group_id) if @table_group_id.present?

    base_query.ordered
  end

  def find_suitable_table
    # 這個方法保持原有邏輯，用於 allocate_table
    find_single_suitable_table
  end

  def find_single_suitable_table
    party_size = total_party_size
    suitable_tables = available_tables.select { |table| table.suitable_for?(party_size) }

    return nil if suitable_tables.empty?

    # 智慧選擇：優先選擇容量最接近需求的桌位，避免資源浪費
    # 1. 先找容量剛好等於需求的桌位
    exact_match = suitable_tables.find { |table| table.capacity == party_size }
    return exact_match if exact_match

    # 2. 找容量略大於需求的桌位，按容量升序排列
    larger_tables = suitable_tables.select { |table| table.capacity > party_size }
      .sort_by { |table| [table.capacity, table.sort_order] }
    return larger_tables.first if larger_tables.any?

    # 3. 如果沒有找到，選擇 max_capacity 能容納需求的桌位
    # 按 max_capacity 升序，再按 sort_order 排序
    suitable_tables.min_by do |table|
      max_cap = table.max_capacity.presence || table.capacity
      [max_cap, table.sort_order]
    end
  end

  def get_reserved_table_ids(datetime)
    return [] unless datetime

    reserved_table_ids = []

    # 如果是無限時模式，檢查同一餐期的衝突（每餐期每桌只有一個訂位）
    if @restaurant.policy.unlimited_dining_time?
      return [] unless @business_period_id # 如果沒有餐期ID，不檢查衝突

      target_date = datetime.to_date
      business_period = BusinessPeriod.find(@business_period_id)

      conflicting_reservations = Reservation.where(restaurant: @restaurant)
        .where(status: %w[pending confirmed])
        .where('DATE(reservation_datetime) = ?', target_date)
        .where(business_period: business_period)
        .includes(:table, table_combination: :restaurant_tables)
    else
      # 使用餐廳設定的用餐時間
      duration_minutes = @restaurant.dining_duration_with_buffer
      return [] unless duration_minutes # 如果沒有設定時間，不檢查衝突

      start_time = datetime
      end_time = datetime + duration_minutes.minutes

      # 計算結束時間以避免 SQL 注入
      reservation_end_time = start_time + duration_minutes.minutes
      conflict_end_time = end_time + duration_minutes.minutes
      
      conflicting_reservations = Reservation.where(restaurant: @restaurant)
        .where(status: %w[pending confirmed])
        .where(
          "(reservation_datetime <= ? AND ? > ?) OR " \
          "(reservation_datetime < ? AND ? >= ?)",
          start_time, reservation_end_time, start_time,
          end_time, conflict_end_time, end_time
        )
        .includes(:table, table_combination: :restaurant_tables)
    end

    # 收集所有被佔用的桌位
    conflicting_reservations.each do |reservation|
      # 收集單一桌位
      reserved_table_ids << reservation.table_id if reservation.table_id.present?

      # 收集併桌中的所有桌位
      if reservation.table_combination.present?
        combination_table_ids = reservation.table_combination.restaurant_tables.pluck(:id)
        reserved_table_ids.concat(combination_table_ids)
      end
    end

    reserved_table_ids.uniq.compact
  end

  def can_combine_tables?
    # 檢查餐廳是否有支援併桌的桌位
    @restaurant.can_combine_tables?
  end

  def can_table_combine?(table)
    # 檢查桌位是否支援併桌
    table.can_combine?
  end

  def find_best_combination_in_group(group_tables, party_size)
    # 簡化：按 sort_order 排序，嘗試最少桌位的組合
    sorted_tables = group_tables.sort_by(&:sort_order)

    max_tables = @restaurant.max_tables_per_combination

    # 嘗試不同的組合大小（從2桌開始到最大允許桌數）
    (2..max_tables).each do |combination_size|
      sorted_tables.combination(combination_size) do |table_combination|
        total_capacity = table_combination.sum(&:capacity)

        # 檢查容量是否足夠
        next unless total_capacity >= party_size

        # 檢查是否所有桌位都可以併桌
        next unless table_combination.all? { |table| can_table_combine?(table) }

        # 不限時模式下，檢查同餐期是否有衝突
        if @restaurant.policy.unlimited_dining_time?
          has_conflict = table_combination.any? do |table|
            booking_check = check_table_booking_in_period(table, @reservation_datetime)
            booking_check[:has_booking]
          end
          next if has_conflict
        end

        return table_combination
      end
    end

    nil
  end

  def exceeds_restaurant_capacity?
    return false unless @restaurant.respond_to?(:total_capacity)

    party_size = total_party_size
    datetime = @reservation&.reservation_datetime || @reservation_datetime

    return false unless datetime

    # 如果是無限時模式，檢查同一餐期的容量
    if @restaurant.policy.unlimited_dining_time?
      return false unless @business_period_id # 如果沒有餐期ID，不檢查容量限制

      target_date = datetime.to_date
      business_period = BusinessPeriod.find(@business_period_id)

      query = Reservation.where(restaurant: @restaurant)
        .where(status: %w[pending confirmed])
        .where('DATE(reservation_datetime) = ?', target_date)
        .where(business_period: business_period)

      # 排除當前正在處理的預訂（如果有的話）

    else
      # 計算該時段已預約的總人數
      duration_minutes = @restaurant.dining_duration_with_buffer
      return false unless duration_minutes # 如果沒有設定時間，不檢查容量限制

      # 計算結束時間以避免 SQL 注入
      end_time = datetime + duration_minutes.minutes
      
      query = Reservation.where(restaurant: @restaurant)
        .where(status: %w[pending confirmed])
        .where(
          "reservation_datetime <= ? AND ? > ?",
          datetime, end_time, datetime
        )

      # 排除當前正在處理的預訂（如果有的話）

    end
    query = query.where.not(id: @reservation.id) if @reservation&.persisted?
    reserved_capacity = query.sum(:party_size)

    # 計算剩餘容量
    total_capacity = @restaurant.total_capacity || @restaurant.restaurant_tables.sum do |t|
      t.max_capacity || t.capacity
    end
    remaining_capacity = total_capacity - reserved_capacity

    # 如果剩餘容量小於所需容量，則超過餐廳容量
    party_size > remaining_capacity
  end

  def create_table_combination(tables)
    return nil unless @reservation
    return nil if tables.count < 2

    combination_name = "併桌 #{tables.map(&:table_number).join(', ')}"

    @reservation.build_table_combination(
      name: combination_name,
      restaurant_tables: tables
    )
  end
end
