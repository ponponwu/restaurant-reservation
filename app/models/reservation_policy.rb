class ReservationPolicy < ApplicationRecord
  # 1. 關聯定義
  belongs_to :restaurant

  # 2. 驗證規則
  validates :advance_booking_days, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :minimum_advance_hours, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_party_size, presence: true, numericality: { greater_than: 0 }
  validates :min_party_size, presence: true, numericality: { greater_than: 0 }
  validates :deposit_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :min_party_size_not_greater_than_max

  # 3. Scope 定義
  scope :with_deposit, -> { where(deposit_required: true) }
  scope :without_deposit, -> { where(deposit_required: false) }

  # 4. 回調函數
  before_validation :set_defaults
  before_validation :sanitize_inputs

  # 5. 實例方法
  def earliest_booking_date
    Date.current + advance_booking_days.days
  end

  def latest_booking_datetime(target_datetime)
    target_datetime - minimum_advance_hours.hours
  end

  def can_book_on_date?(target_date)
    return false if target_date > earliest_booking_date
    true
  end

  def can_book_at_time?(target_datetime)
    latest_allowed = latest_booking_datetime(target_datetime)
    Time.current <= latest_allowed
  end

  def party_size_valid?(size)
    size.between?(min_party_size, max_party_size)
  end

  def calculate_deposit(party_size)
    return 0.0 unless deposit_required?
    
    if deposit_per_person?
      deposit_amount * party_size
    else
      deposit_amount
    end
  end

  def formatted_deposit_policy
    return '無需押金' unless deposit_required?
    
    if deposit_per_person?
      "每人 $#{deposit_amount}"
    else
      "固定金額 $#{deposit_amount}"
    end
  end

  def booking_rules_summary
    rules = []
    rules << "最多提前 #{advance_booking_days} 天預約"
    rules << "最少提前 #{minimum_advance_hours} 小時預約"
    rules << "人數限制：#{min_party_size}-#{max_party_size} 人"
    rules << formatted_deposit_policy
    rules
  end

  # 6. 類別方法
  def self.for_restaurant(restaurant)
    find_or_create_by(restaurant: restaurant)
  end

  # 7. 私有方法
  private

  def set_defaults
    self.advance_booking_days ||= 30
    self.minimum_advance_hours ||= 2
    self.max_party_size ||= 10
    self.min_party_size ||= 1
    self.cancellation_hours ||= 24
    self.deposit_required = false if deposit_required.nil?
    self.deposit_amount ||= 0.0
    self.deposit_per_person = false if deposit_per_person.nil?
    self.special_rules ||= {}
  end

  def sanitize_inputs
    self.no_show_policy = no_show_policy&.strip
    self.modification_policy = modification_policy&.strip
  end

  def min_party_size_not_greater_than_max
    return unless min_party_size && max_party_size
    
    if min_party_size > max_party_size
      errors.add(:min_party_size, '最小人數不能大於最大人數')
    end
  end
end 