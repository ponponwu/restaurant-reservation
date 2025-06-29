class TableGroup < ApplicationRecord
  # 1. 關聯定義
  belongs_to :restaurant
  has_many :restaurant_tables, -> { order(:sort_order) }, dependent: :destroy

  # 2. 驗證規則
  validates :name, presence: true, length: { maximum: 50 }
  validates :sort_order, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # 3. Scope 定義
  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:sort_order, :id) }
  scope :for_restaurant, ->(restaurant_id) { where(restaurant_id: restaurant_id) }

  # 4. 回調函數
  before_validation :set_defaults

  # Ransack 搜索屬性白名單
  def self.ransackable_attributes(_auth_object = nil)
    %w[
      active
      created_at
      description
      id
      name
      restaurant_id
      sort_order
      updated_at
    ]
  end

  # Ransack 搜索關聯白名單
  def self.ransackable_associations(_auth_object = nil)
    %w[
      restaurant
      restaurant_tables
    ]
  end

  # 5. 類別方法
  # 重新排序群組
  def self.reorder!(ordered_ids)
    transaction do
      ordered_ids.each_with_index do |id, index|
        where(id: id).update_all(sort_order: index + 1)
      end
    end
  end

  # 下一個排序號碼
  def self.next_sort_order(restaurant)
    TableGroup.where(restaurant: restaurant).maximum(:sort_order).to_i + 1
  end

  # 6. 實例方法
  def display_name
    name
  end

  def tables_count
    restaurant_tables.active.count
  end

  def total_capacity
    restaurant_tables.active.sum(:capacity)
  end

  def available_tables_count
    restaurant_tables.active.where(operational_status: 'normal').count
  end

  def available_capacity
    restaurant_tables.active.where(operational_status: 'normal').sum(:capacity)
  end

  def occupied_tables_count
    # 透過訂位記錄計算已佔用桌位，而非使用狀態
    current_time = Time.current
    restaurant_tables.active
      .joins(:reservations)
      .where(
        reservations: {
          status: %w[confirmed seated],
          restaurant_id: restaurant.id
        }
      )
      .where("reservations.reservation_datetime <= ? AND reservations.reservation_datetime + INTERVAL '120 minutes' > ?",
             current_time, current_time)
      .select('restaurant_tables.id')
      .distinct
      .count
  end

  # 為了向後相容，保留 tables 方法
  def tables
    restaurant_tables
  end

  # 7. 私有方法
  private

  def set_defaults
    self.sort_order ||= self.class.next_sort_order(restaurant) if restaurant
    self.active = true if active.nil?
    self.name = name&.strip
    self.description = description&.strip
  end
end
