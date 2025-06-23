class ReservationSlot < ApplicationRecord
  # 1. 關聯定義
  belongs_to :business_period

  # 2. 驗證規則
  validates :slot_time, presence: true
  validates :max_capacity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :interval_minutes, presence: true, numericality: { greater_than: 0 }
  validates :reservation_deadline, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # 3. Scope 定義
  scope :active, -> { where(active: true) }
  scope :for_time, ->(time) { where(slot_time: time) }
  scope :ordered, -> { order(:slot_time) }
  scope :available_for_date, lambda { |_date|
    joins(:business_period)
      .where(active: true)
      .where(business_periods: { active: true })
  }

  # 4. 回調函數
  before_validation :set_defaults

  # 5. 實例方法
  def formatted_time
    slot_time.strftime('%H:%M')
  end

  def available_capacity_for_date(date)
    return 0 unless max_capacity.positive?

    # Since reservations don't directly belong to slots, we calculate based on time
    slot_start = Time.zone.parse("#{date.strftime('%Y-%m-%d')} #{slot_time.strftime('%H:%M')}")
    slot_end = slot_start + interval_minutes.minutes

    used_capacity = Reservation
      .joins(:business_period)
      .where(business_period: business_period)
      .where(reservation_datetime: slot_start..slot_end)
      .where(status: 'confirmed')
      .sum(:party_size)

    max_capacity - used_capacity
  end

  def can_accommodate?(party_size, date)
    available_capacity_for_date(date) >= party_size
  end

  def is_available_for_booking?(datetime)
    return false unless active?
    return false unless business_period.active?

    # 檢查是否在預約截止時間之前
    deadline = datetime - reservation_deadline.minutes
    Time.current <= deadline
  end

  def has_capacity_for?(party_size, date)
    return false unless active?
    return false unless business_period.active?

    # 檢查是否有足夠容量
    available_capacity_for_date(date) >= party_size
  end

  # 6. 私有方法
  private

  def set_defaults
    self.active = true if active.nil?
    self.max_capacity ||= 0
    self.interval_minutes ||= 30
    self.reservation_deadline ||= 60
  end
end
