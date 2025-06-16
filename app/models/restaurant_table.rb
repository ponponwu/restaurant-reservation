class RestaurantTable < ApplicationRecord
  belongs_to :restaurant
  belongs_to :table_group
  has_many :reservations, foreign_key: 'table_id', dependent: :restrict_with_error

  validates :table_number, presence: true, length: { maximum: 10 }, uniqueness: { scope: :restaurant_id }
  validates :capacity, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 20 }
  validates :min_capacity, numericality: { greater_than: 0 }
  validates :max_capacity, numericality: { greater_than_or_equal_to: :capacity }, allow_blank: true
  validates :sort_order, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :table_type, presence: true
  validates :status, presence: true

  scope :active, -> { where(active: true) }
  scope :available_for_booking, -> { active.where(operational_status: 'normal') }
  scope :ordered, -> { 
    joins(:table_group)
      .order('table_groups.sort_order ASC, restaurant_tables.sort_order ASC, restaurant_tables.id ASC')
  }
  scope :by_capacity, ->(min, max = nil) { 
    if max
      where(capacity: min..max)
    else
      where('capacity >= ?', min)
    end
  }
  scope :in_group, ->(group_id) { where(table_group_id: group_id) }

  # 重新命名舊的 status enum 以避免衝突，保留向後相容性
  enum status: {
    available: 'available',
    occupied: 'occupied',
    reserved: 'reserved',
    maintenance: 'maintenance',
    cleaning: 'cleaning'
  }, _prefix: :legacy

  # 新的 operational_status - 簡化且有意義的狀態
  enum operational_status: {
    normal: 'normal',              # 正常狀態（取代 available/occupied/reserved）
    maintenance: 'maintenance',    # 維修中  
    cleaning: 'cleaning',          # 清潔中
    out_of_service: 'out_of_service' # 停止服務
  }

  enum table_type: {
    regular: 'regular',
    round: 'round',
    square: 'square',
    booth: 'booth',
    bar: 'bar',
    private_room: 'private_room',
    outdoor: 'outdoor',
    counter: 'counter'
  }

  before_validation :set_defaults
  before_validation :sanitize_inputs
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?
  after_create_commit :update_restaurant_capacity
  after_update_commit :update_restaurant_capacity, if: :saved_change_to_max_capacity_or_active?
  after_destroy_commit :update_restaurant_capacity

  # Ransack 搜索屬性白名單
  def self.ransackable_attributes(auth_object = nil)
    [
      "capacity", 
      "created_at", 
      "id", 
      "max_capacity", 
      "min_capacity", 
      "operational_status", 
      "restaurant_id", 
      "sort_order", 
      "status", 
      "table_group_id", 
      "table_number", 
      "table_type", 
      "updated_at"
    ]
  end

  # Ransack 搜索關聯白名單
  def self.ransackable_associations(auth_object = nil)
    [
      "restaurant",
      "table_group",
      "reservations"
    ]
  end

  def display_name
    "#{table_number} (#{capacity_description})"
  end

  def available?
    # 使用新的 operational_status 邏輯
    normal? && active?
  end

  def can_accommodate?(party_size)
    return false unless available?
    
    min_cap = min_capacity || 1
    max_cap = max_capacity || capacity
    
    party_size >= min_cap && party_size <= max_cap
  end

  def current_reservation
    reservations.where(status: 'confirmed')
                .where('reservation_datetime <= ? AND reservation_datetime + INTERVAL \'120 minutes\' > ?', 
                       Time.current, Time.current)
                .first
  end

  def is_occupied?
    current_reservation.present?
  end

  def available_for_datetime?(datetime, duration_minutes = nil)
    # 如果餐廳是無限用餐時間，則不檢查時間衝突
    return true if restaurant.unlimited_dining_time?
    
    # 使用傳入的時間或餐廳預設時間
    duration_minutes ||= restaurant.dining_duration_with_buffer || 120
    end_time = datetime + duration_minutes.minutes
    
    conflicting_reservations = reservations.where(status: 'confirmed')
      .where(
        "reservation_datetime < ? AND reservation_datetime + (INTERVAL '1 minute' * ?) > ?",
          end_time, duration_minutes.to_i, datetime
      )
    
    conflicting_reservations.empty?
  end

  def capacity_description
    if max_capacity.present? && max_capacity > capacity
      "#{min_capacity}-#{max_capacity}人"
    else
      "#{capacity}人"
    end
  end

  def suitable_for?(party_size)
    return false unless active? && normal?  # 使用 operational_status
    return false if party_size < (min_capacity || 1)
    
    # 檢查容量上限：優先使用 max_capacity，否則使用 capacity
    effective_max_capacity = max_capacity.present? ? max_capacity : capacity
    return false if party_size > effective_max_capacity
    
    true
  end

  # 檢查桌位是否可以併桌
  def can_combine?
    can_combine && active? && normal?
  end

  def global_priority
    # 計算全域優先順序：先按群組順序，再按群組內桌位順序
    return 0 unless table_group&.sort_order && sort_order

    # 獲取所有在此桌位之前的桌位數量
    previous_groups = restaurant.table_groups.active
                                             .where("table_groups.sort_order < ?", table_group.sort_order)
    
    previous_tables_count = previous_groups.joins(:restaurant_tables)
                                         .where(restaurant_tables: { active: true })
                                         .count

    # 加上同群組內在此桌位之前的桌位數量
    same_group_previous_tables = table_group.restaurant_tables.active
                                          .where("restaurant_tables.sort_order < ?", sort_order)
                                          .count

    previous_tables_count + same_group_previous_tables + 1
  end

  # 檢查桌位是否相鄰（用於併桌）
  def adjacent_to?(other_table)
    return false unless other_table.is_a?(RestaurantTable)
    return false if restaurant_id != other_table.restaurant_id
    
    # 如果有位置座標，使用座標計算
    if position_x.present? && position_y.present? && 
       other_table.position_x.present? && other_table.position_y.present?
      distance = Math.sqrt((position_x - other_table.position_x)**2 + 
                          (position_y - other_table.position_y)**2)
      return distance <= 1.5  # 假設相鄰桌位距離不超過1.5單位
    end
    
    # 如果沒有座標，使用桌號相鄰性判斷
    table_nums = [table_number, other_table.table_number].map do |num|
      num.gsub(/\D/, '').to_i
    end
    
    return false if table_nums.any?(&:zero?)
    (table_nums[0] - table_nums[1]).abs <= 1
  end

  # 檢查桌位是否適合特定訂位需求
  def suitable_for_reservation?(reservation)
    return false unless suitable_for?(reservation.party_size)
    
    # 檢查兒童友善需求
    if reservation.children_count > 0
      return false if table_type == 'bar'  # 吧台不適合兒童
      return false unless is_child_friendly != false  # 如果明確標示不適合兒童
    end
    
    # 檢查其他特殊需求
    if reservation.special_requests.present?
      requests = reservation.special_requests.downcase
      
      # 商務聚餐偏好圓桌和安靜環境
      if requests.include?('商務') || requests.include?('會議')
        return false if table_type == 'bar' || table_type == 'counter'
      end
      
      # 檢查安靜需求
      if requests.include?('安靜')
        return false if table_type == 'bar'  # 吧台通常較吵雜
      end
    end
    
    true
  end

  # 檢查桌位可用性並返回詳細信息
  def check_availability(datetime = Time.current, duration_minutes = nil)
    # 如果餐廳是無限用餐時間，使用預設值
    duration_minutes ||= restaurant.dining_duration_with_buffer || 120 unless restaurant.unlimited_dining_time?
    
    {
      available: available_for_datetime?(datetime, duration_minutes),
      operational_status: operational_status,
      current_reservation: current_reservation,
      next_available_time: calculate_next_available_time(datetime),
      conflicts: restaurant.unlimited_dining_time? ? [] : find_conflicting_reservations(datetime, duration_minutes)
    }
  end

  # 計算下次可用時間
  def calculate_next_available_time(from_time = Time.current)
    return from_time if available_for_datetime?(from_time)
    
    # 找下一個結束的訂位
    next_ending_reservation = reservations.where(status: 'confirmed')
                                        .where('reservation_datetime + INTERVAL \'120 minutes\' > ?', from_time)
                                        .order(:reservation_datetime)
                                        .first
    
    if next_ending_reservation
      next_ending_reservation.reservation_datetime + 120.minutes
    else
      from_time
    end
  end

  # 找到衝突的訂位
  def find_conflicting_reservations(datetime, duration_minutes = nil)
    # 如果餐廳是無限用餐時間，不檢查衝突
    return [] if restaurant.unlimited_dining_time?
    
    duration_minutes ||= restaurant.dining_duration_with_buffer || 120
    end_time = datetime + duration_minutes.minutes
    
    reservations.where(status: 'confirmed')
      .where(
        "reservation_datetime < ? AND reservation_datetime + (INTERVAL '1 minute' * ?) > ?",
        end_time, duration_minutes.to_i, datetime
      )
  end

  private

  def set_defaults
    # 如果沒有設定 sort_order，自動分配全域排序
    if sort_order.blank?
      max_sort_order = restaurant&.restaurant_tables&.maximum(:sort_order) || 0
      self.sort_order = max_sort_order + 1
    end
    
    self.status ||= 'available'
    self.operational_status ||= 'normal'
    self.table_type ||= 'regular'
    self.min_capacity ||= 1
    self.max_capacity ||= capacity if capacity.present?
    self.active = true if active.nil?
  end

  def sanitize_inputs
    self.table_number = table_number&.strip
  end

  def broadcast_status_change
    # 廣播桌位狀態變更（用於即時更新）
    # 這裡可以加入 Turbo Stream 廣播邏輯
  end

  def update_restaurant_capacity
    restaurant&.update_cached_capacity
  end

  def saved_change_to_max_capacity_or_active?
    saved_change_to_max_capacity? || saved_change_to_active?
  end

  def self.reorder_in_group!(table_group, ordered_ids)
    transaction do
      # 獲取群組內桌位的當前最小排序
      current_positions = table_group.restaurant_tables.where(id: ordered_ids).pluck(:id, :sort_order).to_h
      min_sort_order = current_positions.values.min
      
      # 更新群組內桌位的排序，保持跨群組的連續性
      ordered_ids.each_with_index do |id, index|
        where(id: id, table_group: table_group).update_all(sort_order: min_sort_order + index)
      end
    end
  end

  def self.next_sort_order_in_group(table_group)
    # 改為全域排序，不再使用群組內排序
    table_group.restaurant.restaurant_tables.maximum(:sort_order).to_i + 1
  end

  # 重新計算餐廳內所有桌位的全域 sort_order
  def self.recalculate_global_sort_order!(restaurant)
    transaction do
      # 按照當前的排序獲取所有桌位，保持相對順序
      tables = restaurant.restaurant_tables
                        .where(active: true)
                        .order(:sort_order, :id)
      
      # 重新分配連續的排序號碼
      tables.each_with_index do |table, index|
        table.update_column(:sort_order, index + 1)
      end
      
      Rails.logger.info "Recalculated sort_order for #{tables.count} tables in restaurant #{restaurant.name}"
    end
  end
end
