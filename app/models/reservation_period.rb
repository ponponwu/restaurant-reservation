class ReservationPeriod < ApplicationRecord
  # 1. 關聯定義
  belongs_to :restaurant
  belongs_to :special_reservation_date, optional: true
  has_many :reservations, dependent: :nullify
  # has_many :waiting_lists, dependent: :nullify  # 暫時註解，等建立 WaitingList 模型後再啟用
  has_many :reservation_slots, dependent: :destroy

  # 2. 星期枚舉定義（每日設定模式）
  CHINESE_WEEKDAYS = {
    0 => '星期日',
    1 => '星期一',
    2 => '星期二',
    3 => '星期三',
    4 => '星期四',
    5 => '星期五',
    6 => '星期六'
  }.freeze

  # 3. 驗證規則
  validates :name, presence: true, length: { maximum: 100 }
  validates :display_name, length: { maximum: 100 }
  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :weekday, presence: true, inclusion: { in: 0..6 }
  validates :reservation_interval_minutes, inclusion: { in: [15, 30, 60, 90, 120, 150, 180, 210, 240] }
  validate :end_time_after_start_time

  # 5. Scope 定義（每日設定查詢）
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :for_weekday, ->(weekday) { where(weekday: weekday) }
  scope :for_date, ->(date) { where(date: date) }
  scope :default_weekly, -> { where(date: nil) }      # 預設週間設定
  scope :specific_date, -> { where.not(date: nil) }   # 特定日期設定
  scope :ordered, -> { order(:start_time) }
  scope :with_slots, -> { includes(:reservation_slots) }

  # 特殊日期相關 scope
  scope :for_special_dates, -> { where(is_special_date_period: true) }
  scope :regular_periods, -> { where(is_special_date_period: false) }
  scope :for_special_reservation_date, ->(special_date) { where(special_reservation_date: special_date) }

  # 6. 回調函數
  before_validation :set_defaults
  before_validation :sanitize_inputs
  after_create :create_default_slots
  after_update :regenerate_slots_if_time_changed
  after_destroy :clear_restaurant_cache
  after_save :clear_restaurant_cache

  # Ransack 搜索屬性白名單
  def self.ransackable_attributes(_auth_object = nil)
    %w[
      active
      created_at
      display_name
      end_time
      id
      name
      restaurant_id
      start_time
      updated_at
      weekday
      date
      reservation_interval_minutes
      special_reservation_date_id
      custom_period_index
      is_special_date_period
    ]
  end

  # Ransack 搜索關聯白名單
  def self.ransackable_associations(_auth_object = nil)
    %w[
      restaurant
      reservations
      reservation_slots
      special_reservation_date
    ]
  end

  # 7. 新的每日設定輔助方法
  def chinese_weekday
    CHINESE_WEEKDAYS[weekday]
  end

  def operates_on_weekday?(check_weekday)
    weekday == check_weekday
  end

  def operates_on_date?(date)
    check_weekday = date.wday

    # 如果有特定日期設定，檢查日期是否匹配
    return self.date == date.to_date if specific_date?

    # 否則檢查星期幾是否匹配
    weekday == check_weekday
  end

  def specific_date?
    date.present?
  end

  def default_weekly?
    date.nil?
  end

  # 特殊日期期間相關方法
  def special_date_period?
    is_special_date_period?
  end

  def regular_period?
    !is_special_date_period?
  end

  def belongs_to_special_date?(special_date)
    special_reservation_date == special_date
  end

  # 8. 實例方法
  def display_name_or_name
    display_name.presence || name
  end

  def full_display_name
    "#{display_name_or_name} (#{formatted_time_range})"
  end

  def display_with_time
    "#{display_name_or_name} (#{formatted_time_range})"
  end

  def formatted_time_range
    "#{local_start_time.strftime('%H:%M')} - #{local_end_time.strftime('%H:%M')}"
  end

  def local_start_time
    start_time.in_time_zone
  end

  def local_end_time
    end_time.in_time_zone
  end

  def duration_minutes
    ((end_time - start_time) / 1.minute).to_i
  end

  def available_on?(date)
    operates_on_date?(date)
  end

  def available_today?
    available_on?(Date.current)
  end

  def current_reservations_count
    reservations.where(
      reservation_datetime: Date.current.all_day,
      status: 'confirmed'
    ).count
  end

  # Phase 6 新增方法
  def reservation_slots_for_date(date)
    return [] unless available_on?(date)

    reservation_slots.active.ordered
  end

  def generate_time_slots(interval_minutes = 30)
    slots = []
    current_time = start_time

    while current_time <= end_time
      slots << current_time
      current_time += interval_minutes.minutes
    end

    slots
  end

  def create_slots_for_interval(interval_minutes = 30)
    # 清除現有時段
    reservation_slots.destroy_all

    # 產生新時段
    generate_time_slots(interval_minutes).each do |slot_time|
      reservation_slots.create!(
        slot_time: slot_time,
        max_capacity: default_slot_capacity,
        interval_minutes: interval_minutes,
        reservation_deadline: default_reservation_deadline
      )
    end
  end

  def settings
    reservation_settings || {}
  end

  def update_settings(new_settings)
    self.reservation_settings = settings.merge(new_settings)
    save!
  end

  # 9. 私有方法
  private

  def set_defaults
    self.active = true if active.nil?
    self.display_name ||= name
    self.reservation_settings ||= {}
    self.reservation_interval_minutes ||= 30
  end

  def sanitize_inputs
    self.name = name&.strip
    self.display_name = display_name&.strip
  end

  def end_time_after_start_time
    return unless start_time && end_time

    return unless end_time <= start_time

    errors.add(:end_time, '結束時間必須晚於開始時間')
  end

  def create_default_slots
    # 在餐期建立後自動建立預設時段（30分鐘間隔）
    create_slots_for_interval(30)
  end

  def default_slot_capacity
    # 預設每個時段的容量（可以從餐廳的總容量計算）
    return 10 unless restaurant&.total_capacity&.positive?

    restaurant.total_capacity / 2 # 假設每個時段可容納一半的桌位
  end

  def default_reservation_deadline
    60 # 預設提前60分鐘截止預約
  end

  def clear_restaurant_cache
    restaurant&.clear_operating_hours_cache
  end

  def regenerate_slots_if_time_changed
    # 檢查是否有時間相關欄位的變更
    time_fields_changed = saved_changes.keys & %w[start_time end_time reservation_interval_minutes]

    return unless time_fields_changed.any?

    Rails.logger.info "🔄 ReservationPeriod #{id}: 時間欄位變更 #{time_fields_changed}, 重新生成 slots"

    # 重新生成時段，使用當前的間隔設定
    create_slots_for_interval(reservation_interval_minutes || 30)
  end
end
