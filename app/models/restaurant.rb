class Restaurant < ApplicationRecord
  # 常數定義
  WEEKDAY_MAPPING = {
    'monday' => 1, 'tuesday' => 2, 'wednesday' => 3, 'thursday' => 4,
    'friday' => 5, 'saturday' => 6, 'sunday' => 0
  }.freeze

  # 1. 關聯定義
  # belongs_to :user, optional: true # 餐廳擁有者 - 暫時註解，等建立 user_id 欄位後再啟用
  has_many :users, dependent: :nullify
  has_many :restaurant_tables, dependent: :destroy
  has_many :table_groups, dependent: :destroy
  has_many :business_periods, dependent: :destroy
  has_many :reservations, dependent: :destroy
  has_many :blacklists, dependent: :destroy
  # has_many :waiting_lists, dependent: :destroy  # 暫時註解，等建立 WaitingList 模型後再啟用
  
  # Phase 6 新增關聯
  has_many :reservation_slots, through: :business_periods
  has_many :closure_dates, dependent: :destroy
  has_one :reservation_policy, dependent: :destroy

  # 2. 驗證規則
  validates :name, presence: true, length: { maximum: 100 }
  validates :phone, presence: true, length: { maximum: 20 }
  validates :address, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 1000 }
  validates :reservation_interval_minutes, presence: true, inclusion: { in: [15, 30, 60], message: '預約間隔必須是 15、30 或 60 分鐘' }

  # 3. Scope 定義
  scope :active, -> { where(active: true, deleted_at: nil) }
  scope :search_by_name, ->(term) { where("name ILIKE ?", "%#{term}%") }
  scope :with_active_periods, -> { joins(:business_periods).where(business_periods: { status: 'active' }) }

  # 4. 回調函數
  before_validation :sanitize_inputs
  after_create :create_default_policy
  after_update :update_cached_capacity, if: :saved_change_to_total_capacity?

  # Slug 相關
  before_validation :generate_slug, if: :will_save_change_to_name?
  validates :slug, presence: true, uniqueness: true

  # Ransack 搜索屬性白名單
  def self.ransackable_attributes(auth_object = nil)
    [
      "active", 
      "address", 
      "created_at", 
      "cuisine_type", 
      "description", 
      "id", 
      "name", 
      "phone", 
      "price_range", 
      "reservation_interval_minutes", 
      "slug", 
      "status", 
      "total_capacity", 
      "updated_at"
    ]
  end

  # Ransack 搜索關聯白名單
  def self.ransackable_associations(auth_object = nil)
    [
      "business_periods",
      "reservations", 
      "restaurant_tables",
      "table_groups"
    ]
  end
  
  # 5. 實例方法

  # 軟刪除
  def soft_delete!
    update!(active: false, deleted_at: Time.current)
  end

  def restore!
    update!(active: true, deleted_at: nil)
  end

  # 用戶統計
  def users_count
    users.active.count
  end

  # 桌位統計
  def total_tables_count
    restaurant_tables.count
  end

  def total_capacity
    # 使用緩存欄位，如果不存在則計算並更新
    self[:total_capacity] || calculate_and_cache_capacity
  end

  def available_tables_count
    restaurant_tables.where(operational_status: 'normal', active: true).count
  end

  # 容量計算和緩存
  def calculate_total_capacity
    restaurant_tables.active.sum { |table| table.max_capacity || table.capacity }
  end

  def calculate_and_cache_capacity
    capacity = calculate_total_capacity
    update_column(:total_capacity, capacity) if persisted?
    capacity
  end

  def update_cached_capacity
    calculate_and_cache_capacity
  end

  # Phase 6 新增方法

  # 營業狀態檢查
  def open_on_date?(date)
    return false unless active?
    return false if closed_on_date?(date)
    
    # 檢查是否有該日期的營業時段
    has_business_period_on_date?(date)
  end

  def closed_on_date?(date)
    # 檢查特定日期的公休
    return true if closure_dates.for_date(date).exists?
    
    # 檢查每週重複的公休
    weekday_number = date.wday # 使用 0-6 格式（週日到週六）
    
    closure_dates.recurring_closures.for_weekday(weekday_number).exists?
  end

  def available_slots_for_date(date)
    return [] unless open_on_date?(date)
    
    day_name = date.strftime('%A').downcase
    business_periods.active
                   .where("days_of_week ? ?", day_name)
                   .includes(:reservation_slots)
                   .flat_map(&:reservation_slots)
                   .select(&:active?)
  end

  # 預約政策
  def policy
    reservation_policy || create_reservation_policy
  end

  def can_accept_reservation?(datetime, party_size)
    return false unless open_on_date?(datetime.to_date)
    return false unless policy.party_size_valid?(party_size)
    return false unless policy.can_book_at_time?(datetime)
    
    true
  end

  def to_param
    slug
  end
  
  # 根據餐廳設定檢查可訂位日期
  def available_dates(start_date = Date.current, days_ahead = 30)
    dates = []
    (start_date..start_date + days_ahead.days).each do |date|
      next if closed_on_date?(date)
      next unless has_business_period_on_date?(date)
      dates << date
    end
    dates
  end
  
  # 根據人數檢查可預約日期
  def available_dates_for_party_size(party_size, end_date = 60.days.from_now)
    start_date = Date.current
    dates = []
    
    (start_date..end_date).each do |date|
      next if closed_on_date?(date)
      next unless has_business_period_on_date?(date)
      next unless has_available_capacity_for_party_size?(party_size, date)
      dates << date.to_s
    end
    
    dates
  end
  
  # 檢查特定日期是否有足夠容量容納指定人數
  def has_capacity_for_party_size?(party_size)
    # 檢查是否有適合該人數的桌位組合
    return false if restaurant_tables.active.empty?
    
    # 檢查是否有單張桌子能容納該人數
    return true if restaurant_tables.active.where('max_capacity >= ?', party_size).exists?
    
    # 檢查是否能透過併桌滿足需求（預留給未來實作）
    false
  end
  
  # 檢查特定日期是否有可用容量
  def has_available_capacity_for_party_size?(party_size, date)
    # 基本容量檢查
    return false unless has_capacity_for_party_size?(party_size)
    
    # 檢查訂位政策是否允許該人數
    return false unless policy.party_size_valid?(party_size)
    
    # 檢查當天是否還有空位（簡化版本，實際需要考慮時段）
    # 這裡暫時假設每天都有空位，實際應該要檢查各時段的訂位情況
    true
  end
  
  # 檢查特定日期是否營業
  def open_on?(date)
    return false if closed_on_date?(date)
    has_business_period_on_date?(date)
  end

  # 檢查特定日期是否有營業時段
  def has_business_period_on_date?(date)
    weekday = date.wday # 使用 0-6 格式
    business_periods.active.any? { |bp| bp.operates_on_weekday?(weekday) }
  end

  # 併桌功能設定
  def allow_table_combinations
    true  # 允許併桌
  end

  # 根據餐期和預約間隔產生可選時間
  def generate_time_slots_for_period(business_period, date = Date.current)
    slots = []
    
    # 餐期開始和結束時間
    start_time = business_period.start_time
    end_time = business_period.end_time
    
    # 結束時間提前2小時（預留用餐時間）
    actual_end_time = end_time - 2.hours
    
    # 從開始時間每隔 reservation_interval_minutes 產生一個時段
    current_time = start_time
    
    while current_time <= actual_end_time
      # 組合日期和時間
      slot_datetime = DateTime.parse("#{date} #{current_time.strftime('%H:%M')}")
      
      # 跳過過去的時間
      if slot_datetime >= DateTime.current
        slots << {
          time: current_time.strftime('%H:%M'),
          datetime: slot_datetime,
          business_period_id: business_period.id
        }
      end
      
      # 增加間隔時間
      current_time += reservation_interval_minutes.minutes
    end
    
    slots
  end

  # 取得指定日期的所有可用時間選項
  def available_time_options_for_date(date)
    slots = []
    
    # 獲取當天營業的餐期（使用 0-6 格式）
    weekday = date.wday
    business_periods.active.each do |period|
      next unless period.operates_on_weekday?(weekday)
      
      period_slots = generate_time_slots_for_period(period, date)
      slots.concat(period_slots)
    end
    
    slots.sort_by { |slot| slot[:time] }
  end

  # 格式化營業時間供前台顯示
  def formatted_business_hours
    
    # 初始化所有週次的資料 - 使用 Array.new 減少分配
    formatted_hours = Array.new(7) do |day_of_week|
      { day_of_week: day_of_week, is_closed: true, periods: [] }
    end
    
    # 一次性載入所有需要的資料，避免 N+1 查詢
    active_periods = business_periods.active.includes(:restaurant)
    recurring_closures = closure_dates.where(recurring: true)
    
    # 處理營業時段
    active_periods.each do |period|
      period.days_of_week.each do |day_name|
        day_index = WEEKDAY_MAPPING[day_name]
        next unless day_index
        
        formatted_hours[day_index][:is_closed] = false
        formatted_hours[day_index][:periods] << {
          name: period.display_name_or_name,
          start_time: period.start_time.strftime('%H:%M'),
          end_time: period.end_time.strftime('%H:%M')
        }
      end
    end
    
    # 處理週間重複公休日設定
    recurring_closures.each do |closure_date|
      next unless closure_date.weekday.present?
      
      # weekday 是 0-6 格式（週日到週六），直接使用
      day_index = closure_date.weekday
      
      if day_index.between?(0, 6)
        formatted_hours[day_index][:is_closed] = true
        formatted_hours[day_index][:periods] = []
      end
    end
    
    formatted_hours
  end

  # 6. 私有方法
  private

  def sanitize_inputs
    self.name = name&.strip
    self.phone = phone&.strip
    self.address = address&.strip
    self.description = description&.strip
  end


  def create_default_policy
    create_reservation_policy unless reservation_policy
  end

  def generate_slug
    if name.present?
      base_slug = name.parameterize
      base_slug = "restaurant-#{id || Time.current.to_i}" if base_slug.blank?
      
      # 確保 slug 唯一性
      counter = 0
      new_slug = base_slug
      while Restaurant.where(slug: new_slug).where.not(id: id).exists?
        counter += 1
        new_slug = "#{base_slug}-#{counter}"
      end
      
      self.slug = new_slug
    end
  end
end
