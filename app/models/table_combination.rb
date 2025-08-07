class TableCombination < ApplicationRecord
  belongs_to :reservation
  has_many :table_combination_tables, dependent: :destroy
  has_many :restaurant_tables, through: :table_combination_tables

  validates :name, presence: true, length: { maximum: 100 }
  validates :reservation_id, uniqueness: { message: '已經被使用' } # 一個訂位只能有一個併桌組合
  validate :must_have_at_least_two_tables
  validate :tables_must_be_combinable
  validate :tables_must_be_available

  scope :active, -> { joins(:reservation).where(reservations: { status: 'confirmed' }) }

  def total_capacity
    restaurant_tables.sum(:capacity)
  end

  def table_numbers
    restaurant_tables.pluck(:table_number).join(', ')
  end

  def can_accommodate?(party_size)
    total_capacity >= party_size
  end

  def display_name
    name.presence || "併桌 #{table_numbers}"
  end

  private

  def must_have_at_least_two_tables
    # 計算已建立的關聯數量（包括新建的）
    tables_count = table_combination_tables.size
    return unless tables_count < 2

    errors.add(:restaurant_tables, '併桌至少需要兩張桌位')
  end

  def tables_must_be_combinable
    return if restaurant_tables.empty?

    # 檢查所有桌位是否都支援併桌
    non_combinable_tables = restaurant_tables.where(can_combine: false)
    if non_combinable_tables.any?
      errors.add(:restaurant_tables, "桌位 #{non_combinable_tables.pluck(:table_number).join(', ')} 不支援併桌")
    end

    # 檢查桌位是否屬於同一餐廳
    restaurant_ids = restaurant_tables.pluck(:restaurant_id).uniq
    errors.add(:restaurant_tables, '併桌的桌位必須屬於同一餐廳') if restaurant_ids.count > 1

    # 檢查桌位是否屬於同一群組（重要：同群組的桌位才能併桌）
    table_group_ids = restaurant_tables.pluck(:table_group_id).uniq
    return unless table_group_ids.count > 1

    errors.add(:restaurant_tables, '併桌的桌位必須屬於同一桌位群組')

    # 檢查桌位是否相鄰（sort_orderso 相近）
    # if restaurant_tables.count > 1
    #   sort_orders = restaurant_tables.pluck(:sort_order).sort
    #   max_gap = sort_orders.each_cons(2).map { |a, b| b - a }.max
    #   if max_gap > 2
    #     errors.add(:restaurant_tables, '併桌的桌位必須相鄰')
    #   end
    # end
  end

  def tables_must_be_available
    return if restaurant_tables.empty? || reservation.blank?
    
    # 如果是管理員覆蓋的預訂，跳過可用性檢查
    return if reservation.admin_override?

    unavailable_tables = restaurant_tables.reject do |table|
      table.available_for_datetime?(reservation.reservation_datetime, exclude_reservation: reservation)
    end

    return unless unavailable_tables.any?

    errors.add(:restaurant_tables, "桌位 #{unavailable_tables.map(&:table_number).join(', ')} 在該時段不可用")
  end
end
