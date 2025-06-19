class BusinessPeriod < ApplicationRecord
  # 1. 關聯定義
  belongs_to :restaurant
  has_many :reservations, dependent: :nullify
  # has_many :waiting_lists, dependent: :nullify  # 暫時註解，等建立 WaitingList 模型後再啟用
  has_many :reservation_slots, dependent: :destroy

  # 2. 星期枚舉定義（使用 bitmask）
  DAYS_OF_WEEK = {
    monday: 1,      # 0000001
    tuesday: 2,     # 0000010  
    wednesday: 4,   # 0000100
    thursday: 8,    # 0001000
    friday: 16,     # 0010000
    saturday: 32,   # 0100000
    sunday: 64      # 1000000
  }.freeze

  CHINESE_DAYS = {
    monday: '星期一',
    tuesday: '星期二',
    wednesday: '星期三',
    thursday: '星期四',
    friday: '星期五',
    saturday: '星期六',
    sunday: '星期日'
  }.freeze

  # 3. 驗證規則
  validates :name, presence: true, length: { maximum: 100 }
  validates :display_name, length: { maximum: 100 }
  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :days_of_week_mask, presence: true, numericality: { greater_than: 0 }
  validate :end_time_after_start_time

  # 4. Scope 定義（狀態相關）
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  # 5. Scope 定義（使用 bitmask 查詢）
  scope :for_day, ->(day) { 
    day_bit = case day
              when Symbol
                DAYS_OF_WEEK[day]
              when String
                DAYS_OF_WEEK[day.downcase.to_sym]
              when Date, Time
                DAYS_OF_WEEK[day.strftime('%A').downcase.to_sym]
              when Integer
                weekday_to_bit(day)
              else
                nil
              end
    where("days_of_week_mask & ? > 0", day_bit) if day_bit
  }
  
  # 新增支援 0-6 格式的 scope
  scope :for_weekday, ->(weekday) { 
    return none unless weekday.is_a?(Integer) && weekday.between?(0, 6)
    bit = weekday_to_bit(weekday)
    where("days_of_week_mask & ? > 0", bit)
  }
  scope :ordered, -> { order(:start_time) }
  scope :with_slots, -> { includes(:reservation_slots) }

  # 6. 回調函數
  before_validation :set_defaults
  before_validation :sanitize_inputs
  after_create :create_default_slots

  # Ransack 搜索屬性白名單
  def self.ransackable_attributes(auth_object = nil)
    [
      "active", 
      "created_at", 
      "days_of_week_mask", 
      "display_name", 
      "end_time", 
      "id", 
      "name", 
      "restaurant_id", 
      "start_time", 
      "updated_at"
    ]
  end

  # Ransack 搜索關聯白名單
  def self.ransackable_associations(auth_object = nil)
    [
      "restaurant",
      "reservations", 
      "reservation_slots"
    ]
  end

  # 7. Days of week 輔助方法（bitmask 版本）
  def days_of_week
    return [] unless days_of_week_mask&.positive?
    DAYS_OF_WEEK.select { |day, bit| (days_of_week_mask & bit) > 0 }.keys.map(&:to_s)
  end
  
  def days_of_week=(day_names)
    return self.days_of_week_mask = 0 if day_names.blank?
    
    self.days_of_week_mask = Array(day_names).sum do |day|
      day_sym = day.to_s.downcase.to_sym
      DAYS_OF_WEEK[day_sym] || 0
    end
  end
  
  def operates_on_day?(day)
    day_bit = case day
              when Symbol
                DAYS_OF_WEEK[day]
              when String
                DAYS_OF_WEEK[day.downcase.to_sym]
              when Date, Time
                DAYS_OF_WEEK[day.strftime('%A').downcase.to_sym]
              when Integer
                self.class.weekday_to_bit(day)
              else
                return false
              end
    return false unless day_bit
    (days_of_week_mask & day_bit) > 0
  end

  # 支援 0-6 格式的檢查方法
  def operates_on_weekday?(weekday)
    return false unless weekday.is_a?(Integer) && weekday.between?(0, 6)
    bit = self.class.weekday_to_bit(weekday)
    (days_of_week_mask & bit) > 0
  end

  def chinese_days_of_week
    days_of_week.map { |day| CHINESE_DAYS[day.to_sym] }.compact
  end

  def formatted_days_of_week
    chinese_days_of_week.join('、')
  end

  # 7.5 類別方法（支援 0-6 格式）
  def self.weekday_to_bit(weekday)
    return nil unless weekday.is_a?(Integer) && weekday.between?(0, 6)
    
    # 0-6 格式轉換為 bitmask
    day_symbols = [:sunday, :monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
    day_symbol = day_symbols[weekday]
    DAYS_OF_WEEK[day_symbol]
  end

  def self.bit_to_weekday(bit)
    return nil unless bit && bit > 0
    
    DAYS_OF_WEEK.each do |day_symbol, day_bit|
      if day_bit == bit
        day_symbols = [:sunday, :monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
        return day_symbols.index(day_symbol)
      end
    end
    nil
  end

  # 8. 實例方法
  def display_name_or_name
    display_name.present? ? display_name : name
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
    operates_on_day?(date)
  end

  def available_today?
    available_on?(Date.current)
  end

  def operates_on_date?(date)
    available_on?(date)
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
    
    while current_time < end_time
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
    self.days_of_week_mask ||= 0
    self.display_name ||= name
    self.reservation_settings ||= {}
    self.active = true if active.nil?
  end

  def sanitize_inputs
    self.name = name&.strip
    self.display_name = display_name&.strip
  end

  def end_time_after_start_time
    return unless start_time && end_time
    
    if end_time <= start_time
      errors.add(:end_time, '結束時間必須晚於開始時間')
    end
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
end
