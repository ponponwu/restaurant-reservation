class ReservationAllocatorService
  # 初始化時可以傳入 reservation 物件或個別參數
  def initialize(params)
    if params.is_a?(Reservation)
      @reservation = params
      @restaurant = params.restaurant
    else
      @restaurant = params[:restaurant]
      @party_size = params[:party_size] || params[:guest_count]
      @adults = params[:adults] || 0
      @children = params[:children] || params[:child_count] || 0
      @reservation_datetime = params[:reservation_datetime] || 
                             DateTime.parse("#{params[:date]} #{params[:time]}")
      @business_period_id = params[:business_period_id]
      @table_group_id = params[:table_group_id]
    end
  end

  def allocate_table
    return nil if (@party_size || total_party_size) < 1
    return nil if exceeds_restaurant_capacity?

    # 先嘗試找單一桌位
    if table = find_suitable_table
      return table
    end

    # 如果找不到單一桌位，檢查是否可以併桌
    if @restaurant.allow_table_combinations && (tables = find_combinable_tables)
      return create_table_combination(tables)
    end

    nil
  end

  def find_available_tables
    available_tables.select { |table| table.suitable_for?(total_party_size) }
  end

  def check_availability
    {
      has_availability: find_suitable_table.present?,
      available_tables: find_available_tables,
      can_combine: can_combine_tables?,
      combinable_tables: find_combinable_tables || []
    }
  end

  def find_combinable_tables
    return nil unless can_combine_tables?

    party_size = total_party_size
    combinable_tables = available_tables.select { |table| can_table_combine?(table) }
    
    return nil if combinable_tables.empty?
    
    # 按桌位群組分組，確保併桌的桌位來自同一群組
    tables_by_group = combinable_tables.group_by(&:table_group_id)
    
    # 嘗試每個群組，找到最佳的桌位組合
    tables_by_group.each do |group_id, group_tables|
      combination = find_best_combination_in_group(group_tables, party_size)
      return combination if combination
    end
    
    nil
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
    base_query = base_query.where.not(table_type: 'bar') if children_count > 0

    # 如果指定了桌位群組，只查詢該群組的桌位
    if @table_group_id.present?
      base_query = base_query.where(table_group_id: @table_group_id)
    end

    base_query.ordered
  end

  def find_suitable_table
    party_size = total_party_size
    suitable_tables = available_tables.select { |table| table.suitable_for?(party_size) }
    
    return nil if suitable_tables.empty?
    
    # 按照優先級排序：窗邊圓桌 > 方桌 > 吧檯
    prioritized_tables = prioritize_tables(suitable_tables, party_size)
    
    # 直接選擇第一個桌位（已經按照 sort_order 排序）
    prioritized_tables.first
  end

  def get_reserved_table_ids(datetime)
    return [] unless datetime

    # 計算訂位時段（假設每個訂位佔用2小時）
    duration_hours = 2
    start_time = datetime
    end_time = datetime + duration_hours.hours

    Reservation.joins(:table)
               .where(restaurant: @restaurant)
               .where(status: ['pending', 'confirmed', 'seated'])
               .where(
                 "(reservation_datetime <= ? AND reservation_datetime + INTERVAL '2 hours' > ?) OR " +
                 "(reservation_datetime < ? AND reservation_datetime + INTERVAL '2 hours' >= ?)",
                 start_time, start_time,
                 end_time, end_time
               )
               .pluck(:table_id)
               .compact
  end

  def can_combine_tables?
    # 檢查餐廳是否允許併桌
    return false unless @restaurant.respond_to?(:allow_table_combinations) && @restaurant.allow_table_combinations
    
    # 暫時簡化：如果餐廳允許併桌，就允許（之後可以加入更詳細的群組設定）
    true
  end

  def can_table_combine?(table)
    # 暫時簡化：如果桌位有 can_combine 屬性且為 true，就允許
    return table.can_combine if table.respond_to?(:can_combine)
    
    # 如果沒有 can_combine 屬性，預設允許
    true
  end

  def prioritize_tables(tables, party_size)
    # 保持 available_tables.ordered 的排序，只優先選擇在容量區間內的桌位
    # available_tables 已經按照 table_groups.sort_order 和 restaurant_tables.sort_order 排序
    
    # 將桌位分成兩組：在容量區間內的 vs 不在區間內的
    in_range_tables = []
    out_of_range_tables = []
    
    tables.each do |table|
      min_cap = table.min_capacity || 1
      max_cap = table.max_capacity || table.capacity
      is_in_range = party_size >= min_cap && party_size <= max_cap
      
      if is_in_range
        in_range_tables << table
      else
        out_of_range_tables << table
      end
    end
    
    # 優先返回在容量區間內的桌位，保持原始排序
    # 如果沒有在區間內的桌位，再考慮區間外的桌位
    in_range_tables + out_of_range_tables
  end

  def find_best_combination_in_group(group_tables, party_size)
    # 按照容量從小到大排序，優先使用小桌位
    sorted_tables = group_tables.sort_by(&:capacity)
    
    # 嘗試兩張桌位的組合
    sorted_tables.combination(2).each do |table_pair|
      total_capacity = table_pair.sum(&:capacity)
      if total_capacity >= party_size && total_capacity <= party_size + 2 # 避免浪費太多容量
        return table_pair
      end
    end
    
    # 如果兩張不夠，嘗試三張桌位的組合
    if sorted_tables.count >= 3
      sorted_tables.combination(3).each do |table_trio|
        total_capacity = table_trio.sum(&:capacity)
        if total_capacity >= party_size && total_capacity <= party_size + 3
          return table_trio
        end
      end
    end
    
    nil
  end

  def exceeds_restaurant_capacity?
    return false unless @restaurant.respond_to?(:total_capacity)
    
    party_size = total_party_size
    datetime = @reservation&.reservation_datetime || @reservation_datetime
    
    return false unless datetime
    
    # 計算該時段已預約的總人數
    reserved_capacity = Reservation.where(restaurant: @restaurant)
                                  .where(status: ['pending', 'confirmed', 'seated'])
                                  .where(
                                    "reservation_datetime <= ? AND reservation_datetime + INTERVAL '2 hours' > ?",
                                    datetime, datetime
                                  )
                                  .sum(:party_size)

    # 計算剩餘容量
    total_capacity = @restaurant.total_capacity || @restaurant.restaurant_tables.sum { |t| t.max_capacity || t.capacity }
    remaining_capacity = total_capacity - reserved_capacity

    # 如果剩餘容量小於所需容量，則超過餐廳容量
    party_size > remaining_capacity
  end

  def create_table_combination(tables)
    return nil unless @reservation
    
    # 創建併桌組合
    combination = TableCombination.new(
      reservation: @reservation,
      name: "併桌 #{tables.map(&:table_number).join('+')}"
    )
    
    # 建立桌位關聯
    tables.each do |table|
      combination.table_combination_tables.build(restaurant_table: table)
    end
    
    if combination.save
      # 返回第一個桌位作為主桌位（用於相容性）
      tables.first
    else
      nil
    end
  end
end 