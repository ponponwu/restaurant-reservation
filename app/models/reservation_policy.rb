class ReservationPolicy < ApplicationRecord
  # 1. 關聯定義
  belongs_to :restaurant

  # 2. 驗證規則
  validates :advance_booking_days, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :minimum_advance_hours, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_party_size, presence: true, numericality: { greater_than: 0 }
  validates :min_party_size, presence: true, numericality: { greater_than: 0 }
  validates :deposit_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_bookings_per_phone, presence: true, numericality: { greater_than: 0 }
  validates :phone_limit_period_days, presence: true, numericality: { greater_than: 0 }
  validates :default_dining_duration_minutes, presence: true, numericality: { greater_than: 0 },
                                              unless: :unlimited_dining_time?
  validates :buffer_time_minutes, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_combination_tables, presence: true, numericality: { greater_than: 1 }
  validate :min_party_size_not_greater_than_max

  # 3. Scope 定義
  scope :requiring_deposit, -> { where(deposit_required: true) }
  scope :not_requiring_deposit, -> { where(deposit_required: false) }

  # 4. 回調函數
  before_validation :set_defaults
  before_validation :sanitize_inputs

  # 5. 實例方法
  def earliest_booking_date
    Date.current + advance_booking_days.days
  end

  def latest_booking_datetime
    Time.current + minimum_advance_hours.hours
  end

  def can_book_on_date?(target_date)
    # 不能超過預定範圍
    return false if target_date > earliest_booking_date

    true
  end

  def can_book_at_time?(target_datetime)
    # 必須符合最少提前預定時間
    target_datetime >= latest_booking_datetime
  end

  def party_size_valid?(size)
    size.between?(min_party_size, max_party_size)
  end

  def calculate_deposit(party_size)
    return 0 unless deposit_required?

    if deposit_per_person?
      deposit_amount * party_size
    else
      deposit_amount
    end
  end

  def formatted_deposit_policy
    return '無需押金' unless deposit_required?

    formatted_amount = deposit_amount.to_i == deposit_amount ? deposit_amount.to_i : deposit_amount

    if deposit_per_person?
      "每人 $#{formatted_amount}"
    else
      "固定金額 $#{formatted_amount}"
    end
  end

  def booking_rules_summary
    rules = []
    rules << "最多提前 #{advance_booking_days} 天預約"
    rules << "最少提前 #{minimum_advance_hours} 小時預約"
    rules << "人數限制：#{min_party_size}-#{max_party_size} 人"
    rules << formatted_deposit_policy
    rules << "單一手機號碼 #{phone_limit_period_days} 天內最多訂位 #{max_bookings_per_phone} 次"
    rules
  end

  # 檢查手機號碼是否超過訂位限制
  def phone_booking_limit_exceeded?(phone_number)
    return false if phone_number.blank?

    current_bookings = count_phone_bookings_in_period(phone_number)
    current_bookings >= max_bookings_per_phone
  end

  # 計算手機號碼在指定期間內的訂位次數
  def count_phone_bookings_in_period(phone_number)
    return 0 if phone_number.blank?

    start_date = Date.current
    end_date = start_date + phone_limit_period_days.days

    restaurant.reservations
      .where(customer_phone: phone_number)
      .where(reservation_datetime: start_date.beginning_of_day..end_date.end_of_day)
      .where.not(status: %i[cancelled no_show])
      .count
  end

  # 獲取手機號碼剩餘可訂位次數
  def remaining_bookings_for_phone(phone_number)
    return max_bookings_per_phone if phone_number.blank?

    current_bookings = count_phone_bookings_in_period(phone_number)
    [max_bookings_per_phone - current_bookings, 0].max
  end

  # 格式化手機號碼限制說明
  def formatted_phone_limit_policy
    "同一手機號碼在#{phone_limit_period_days}天內最多只能建立#{max_bookings_per_phone}個有效訂位"
  end

  # 檢查餐廳是否接受線上訂位
  def accepts_online_reservations?
    reservation_enabled?
  end

  # 獲取訂位功能關閉的原因說明
  def reservation_disabled_message
    return if reservation_enabled?

    '線上訂位功能暫停服務，如需訂位請直接致電餐廳'
  end

  # 檢查是否可以在指定日期時間預定
  def can_reserve_at?(target_datetime)
    # 檢查是否在允許的預定範圍內
    return false unless can_book_on_date?(target_datetime.to_date)

    # 檢查是否符合提前預定時間要求
    return false unless can_book_at_time?(target_datetime)

    true
  end

  # 獲取不能預定的原因
  def reservation_rejection_reason(target_datetime)
    if target_datetime.to_date > earliest_booking_date
      "超出最大預定範圍（最多提前 #{advance_booking_days} 天）"
    elsif target_datetime < latest_booking_datetime
      "預定時間過近（至少提前 #{minimum_advance_hours} 小時）"
    end
  end

  # 用餐時間相關方法
  def total_dining_duration_minutes
    return nil if unlimited_dining_time?

    default_dining_duration_minutes + buffer_time_minutes
  end

  def has_time_limit?
    !unlimited_dining_time?
  end

  def dining_settings_summary
    if unlimited_dining_time?
      '無限用餐時間'
    else
      "用餐時間：#{default_dining_duration_minutes}分鐘 + 緩衝#{buffer_time_minutes}分鐘 = #{total_dining_duration_minutes}分鐘"
    end
  end

  def table_combination_settings_summary
    if allow_table_combinations?
      "允許併桌（最多#{max_combination_tables}桌）"
    else
      '不允許併桌'
    end
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
    self.max_bookings_per_phone ||= 5
    self.phone_limit_period_days ||= 30
    self.reservation_enabled = true if reservation_enabled.nil?
    self.special_rules ||= {}

    # 用餐時間設定預設值
    self.unlimited_dining_time = false if unlimited_dining_time.nil?
    self.default_dining_duration_minutes ||= 120
    self.buffer_time_minutes ||= 15
    self.allow_table_combinations = true if allow_table_combinations.nil?
    self.max_combination_tables ||= 3
  end

  def sanitize_inputs
    self.no_show_policy = no_show_policy&.strip
    self.modification_policy = modification_policy&.strip
  end

  def min_party_size_not_greater_than_max
    return unless min_party_size && max_party_size

    return unless min_party_size > max_party_size

    errors.add(:min_party_size, '最小人數不能大於最大人數')
  end
end
