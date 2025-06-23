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
  has_many :table_combinations, through: :reservations
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
  validates :reservation_interval_minutes, presence: true,
                                           inclusion: { in: [15, 30, 60], message: '預約間隔必須是 15、30 或 60 分鐘' }

  # 新增欄位驗證
  validates :business_name, length: { maximum: 100 }
  validates :tax_id, length: { maximum: 20 }
  validates :reminder_notes, length: { maximum: 2000 }

  # 3. Scope 定義
  scope :active, -> { where(active: true, deleted_at: nil) }
  scope :search_by_name, ->(term) { where('name ILIKE ?', "%#{term}%") }
  scope :with_active_periods, -> { joins(:business_periods).where(business_periods: { status: 'active' }) }

  # 4. 回調函數
  before_validation :sanitize_inputs
  # Slug 相關
  before_validation :generate_slug, if: :will_save_change_to_name?
  after_create :create_default_policy
  after_update :update_cached_capacity, if: :saved_change_to_total_capacity?

  validates :slug, presence: true, uniqueness: true

  # Ransack 搜索屬性白名單
  def self.ransackable_attributes(_auth_object = nil)
    %w[
      active
      address
      created_at
      cuisine_type
      description
      id
      name
      phone
      price_range
      reservation_interval_minutes
      slug
      status
      total_capacity
      updated_at
    ]
  end

  # Ransack 搜索關聯白名單
  def self.ransackable_associations(_auth_object = nil)
    %w[
      business_periods
      reservations
      restaurant_tables
      table_groups
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
    # 使用緩存欄位，如果為0（未計算）則計算並更新
    cached_capacity = self[:total_capacity]
    if cached_capacity.nil? || cached_capacity == 0
      calculate_and_cache_capacity
    else
      cached_capacity
    end
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
      .where('days_of_week ? ?', day_name)
      .includes(:reservation_slots)
      .flat_map(&:reservation_slots)
      .select(&:active?)
  end

  # 預約政策
  def policy
    return reservation_policy if reservation_policy.present?
    return nil unless persisted? # 如果 restaurant 還沒保存，返回 nil

    reservation_policy || create_reservation_policy
  end

  def can_accept_reservation?(datetime, party_size)
    return false unless open_on_date?(datetime.to_date)
    return false unless policy&.party_size_valid?(party_size)
    return false unless policy&.can_book_at_time?(datetime)

    true
  end

  def to_param
    slug
  end

  # 根據餐廳設定檢查可訂位日期
  def available_dates(start_date = Date.current, days_ahead = 30)
    dates = []
    (start_date..(start_date + days_ahead.days)).each do |date|
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
    return false if party_size <= 0

    # 檢查單桌是否能容納
    return true if restaurant_tables.active.any? { |table| table.capacity >= party_size }

    # 檢查併桌是否能容納（如果允許併桌）
    if can_combine_tables?
      max_combinable_capacity = restaurant_tables.active
        .where(can_combine: true)
        .limit(max_tables_per_combination)
        .sum(:capacity)
      return true if max_combinable_capacity >= party_size
    end

    false
  end

  # 檢查特定日期是否有可用容量
  def has_available_capacity_for_party_size?(party_size, _date)
    # 基本容量檢查
    return false unless has_capacity_for_party_size?(party_size)

    # 檢查訂位政策是否允許該人數
    return false unless policy&.party_size_valid?(party_size)

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

  # 用餐時間相關方法（委派給 reservation_policy）
  def unlimited_dining_time?
    policy&.unlimited_dining_time? || false
  end

  def limited_dining_time?
    !unlimited_dining_time?
  end

  def dining_duration_minutes
    return nil if unlimited_dining_time?

    policy&.default_dining_duration_minutes || 120
  end

  def dining_duration_with_buffer
    return nil if unlimited_dining_time?

    dining_duration_minutes + (policy&.buffer_time_minutes || 15)
  end

  def can_combine_tables?
    # 使用實例變數快取結果，避免重複查詢
    @can_combine_tables ||= policy&.allow_table_combinations? && restaurant_tables.active.exists?(can_combine: true)
  end

  def max_tables_per_combination
    policy&.max_combination_tables || 3
  end

  # 委派給 reservation_policy 的併桌設定
  def allow_table_combinations?
    policy&.allow_table_combinations? || false
  end

  # 根據餐期和預約間隔產生可選時間
  def generate_time_slots_for_period(business_period, date = Date.current)
    slots = []

    # 餐期開始和結束時間 - 使用本地時間避免時區問題
    start_time = business_period.local_start_time
    end_time = business_period.local_end_time

    # 結束時間提前2小時（預留用餐時間）
    actual_end_time = end_time - 2.hours

    # 獲取最小提前預訂時間
    minimum_advance_hours = policy&.minimum_advance_hours || 0
    earliest_booking_time = Time.current + minimum_advance_hours.hours

    # 從開始時間每隔 reservation_interval_minutes 產生一個時段
    current_time = start_time

    while current_time <= actual_end_time
      # 正確組合日期和時間，保持時區一致性
      slot_datetime = Time.zone.parse("#{date} #{current_time.strftime('%H:%M')}")

      # 跳過過去的時間，並檢查是否符合最小提前預訂時間
      if slot_datetime >= earliest_booking_time
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

  # 取得指定日期的所有可用時間選項（優化版本）
  def available_time_options_for_date(date)
    # 使用實例變數快取，避免重複計算同一天的時間選項
    @time_options_cache ||= {}
    cache_key = date.to_s

    return @time_options_cache[cache_key] if @time_options_cache[cache_key]

    slots = []

    # 獲取當天營業的餐期（使用 0-6 格式）
    weekday = date.wday

    # 使用實例變數快取活躍的營業時段，避免重複查詢
    @cached_active_periods ||= business_periods.active.includes(:restaurant).to_a

    @cached_active_periods.each do |period|
      next unless period.operates_on_weekday?(weekday)

      period_slots = generate_time_slots_for_period(period, date)
      slots.concat(period_slots)
    end

    # 快取結果
    @time_options_cache[cache_key] = slots.sort_by { |slot| slot[:time] }
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
      next if closure_date.weekday.blank?

      # weekday 是 0-6 格式（週日到週六），直接使用
      day_index = closure_date.weekday

      if day_index.between?(0, 6)
        formatted_hours[day_index][:is_closed] = true
        formatted_hours[day_index][:periods] = []
      end
    end

    formatted_hours
  end

  # 格式化提醒事項
  def formatted_reminder_notes
    return [] if reminder_notes.blank?

    # 將提醒事項按行分割，並過濾空行
    reminder_notes.split("\n").map(&:strip).compact_blank
  end

  # 檢查是否有營業資訊
  def has_business_info?
    business_name.present? || tax_id.present?
  end

  # 格式化營業資訊
  def formatted_business_info
    info = []
    info << "營業人名稱：#{business_name}" if business_name.present?
    info << "統一編號：#{tax_id}" if tax_id.present?
    info
  end

  # 6. 私有方法
  private

  def sanitize_inputs
    self.name = name&.strip
    self.phone = phone&.strip
    self.address = address&.strip
    self.description = description&.strip
    self.business_name = business_name&.strip
    self.tax_id = tax_id&.strip
    self.reminder_notes = reminder_notes&.strip
  end

  def create_default_policy
    create_reservation_policy unless reservation_policy
  end

  def generate_slug
    return if name.blank?

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
