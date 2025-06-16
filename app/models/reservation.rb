class Reservation < ApplicationRecord
  # 1. 關聯定義（放在最前面）
  belongs_to :restaurant
  belongs_to :table, optional: true, foreign_key: 'table_id', class_name: 'RestaurantTable'
  belongs_to :business_period, optional: true
  has_one :table_combination, dependent: :destroy
  
  # 向後相容性方法
  alias_method :restaurant_table, :table
  alias_method :restaurant_table=, :table=
  
  # 2. 驗證規則
  validates :customer_name, presence: true, length: { maximum: 50 }
  validates :customer_phone, presence: true, format: { with: /\A\d{8,15}\z/, message: '請輸入有效的電話號碼' }
  validates :customer_email, format: { with: URI::MailTo::EMAIL_REGEXP, message: '請輸入有效的電子郵件' }, allow_blank: true
  validates :party_size, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 20 }
  validates :reservation_datetime, presence: true
  validates :status, presence: true
  validates :adults_count, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 20 }
  validates :children_count, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 20 }
  validate :reservation_datetime_in_future, on: :create
  validate :party_size_within_restaurant_limits
  validate :party_size_matches_adults_and_children
  validate :customer_not_blacklisted, on: :create
  
  # 3. Scope 定義
  scope :active, -> { where.not(status: %w[cancelled no_show]) }
  scope :for_date, ->(date) { where(reservation_datetime: date.all_day) }
  scope :for_time_range, ->(start_time, end_time) { where(reservation_datetime: start_time..end_time) }
  scope :with_adults, ->(count) { where(adults_count: count) }
  scope :with_children, ->(count) { where(children_count: count) }
  scope :large_party, ->(size) { where('party_size >= ?', size) }
  scope :confirmed, -> { where(status: 'confirmed') }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_datetime, -> { order(:reservation_datetime) }
  
  # 4. 枚舉定義
  enum status: {
    pending: 'pending',
    confirmed: 'confirmed',
    cancelled: 'cancelled',
    no_show: 'no_show'
  }

  # Ransack 搜索屬性白名單
  def self.ransackable_attributes(auth_object = nil)
    %w[
      adults_count business_period_id children_count created_at 
      customer_email customer_name customer_phone id party_size 
      reservation_datetime restaurant_id special_requests status 
      table_id updated_at
    ]
  end

  # Ransack 搜索關聯白名單
  def self.ransackable_associations(auth_object = nil)
    %w[business_period restaurant table table_combination]
  end
  
  # 5. 回調函數
  before_validation :sanitize_inputs
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?
  
  # 6. 實例方法
  def display_name
    "#{customer_name} (#{party_size}人) - #{formatted_datetime}"
  end

  def formatted_datetime
    reservation_datetime.strftime('%Y/%m/%d %H:%M')
  end

  def formatted_date
    reservation_datetime.strftime('%Y/%m/%d')
  end

  def formatted_time
    reservation_datetime.strftime('%H:%M')
  end

  def can_cancel?
    pending? || confirmed?
  end

  def can_modify?
    pending? || confirmed?
  end

  def can_mark_no_show?
    confirmed? && is_past?
  end

  def is_today?
    reservation_datetime.to_date == Date.current
  end

  def is_past?
    reservation_datetime < Time.current
  end

  def time_until_reservation
    return 0 if is_past?
    ((reservation_datetime - Time.current) / 1.hour).round(1)
  end

  def estimated_end_time
    duration = 120 # 暫時使用固定值，等 restaurant.setting 方法實作後再改回
    reservation_datetime + duration.minutes
  end

  def has_assigned_table?
    table.present? || has_table_combination?
  end

  def table_capacity
    if has_table_combination?
      table_combination.total_capacity
    else
      table&.capacity || 0
    end
  end
  
  def has_table_combination?
    table_combination.present?
  end
  
  def assigned_tables
    if has_table_combination?
      table_combination.restaurant_tables
    elsif table.present?
      [table]
    else
      []
    end
  end
  
  def table_display_name
    if has_table_combination?
      table_combination.display_name
    elsif table.present?
      table.table_number
    else
      '未分配'
    end
  end

  # 檢查是否需要無障礙設施


  # 檢查是否為家庭客戶（有兒童）
  def family_with_children?
    children_count > 0
  end

  # 檢查是否為商務聚餐
  # def business_meeting?
  #   return false if special_requests.blank?
    
  #   business_keywords = %w[商務 會議 business meeting corporate]
  #   business_keywords.any? { |keyword| special_requests.downcase.include?(keyword) }
  # end

  # 計算總用餐時間（包含緩衝時間）
  def total_duration_minutes
    return nil if restaurant&.policy&.unlimited_dining_time?  # 無限時模式回傳 nil
    restaurant&.dining_duration_with_buffer || 135  # 預設 120 分鐘 + 15 分鐘緩衝
  end

  # 計算佔用時間範圍
  def occupation_time_range
    return nil if restaurant&.policy&.unlimited_dining_time?  # 無限時模式沒有結束時間
    
    duration = total_duration_minutes
    return nil unless duration  # 如果沒有設定時間，回傳 nil
    
    end_time = reservation_datetime + duration.minutes
    reservation_datetime..end_time
  end

  # 快取失效回調
  after_create :clear_availability_cache
  after_update :clear_availability_cache, if: :saved_change_to_status?
  after_destroy :clear_availability_cache

  # 7. 私有方法
  private

  def sanitize_inputs
    self.customer_name = customer_name&.strip
    self.customer_phone = customer_phone&.gsub(/\D/, '')
    self.customer_email = customer_email&.strip&.downcase
    self.special_requests = special_requests&.strip
    self.notes = notes&.strip
  end

  def reservation_datetime_in_future
    return unless reservation_datetime
    
    min_advance_hours = 1 # 暫時使用固定值
    min_datetime = Time.current + min_advance_hours.hours
    
    if reservation_datetime < min_datetime
      errors.add(:reservation_datetime, "訂位時間必須至少提前 #{min_advance_hours} 小時")
    end
  end

  def party_size_within_restaurant_limits
    return unless restaurant && party_size
    
    policy = restaurant.reservation_policy
    max_party_size = policy&.max_party_size || 12
    
    if party_size > max_party_size
      errors.add(:party_size, "人數不能超過 #{max_party_size} 人")
    end
  end

  def party_size_matches_adults_and_children
    return unless adults_count && children_count && party_size
    
    if adults_count + children_count != party_size
      errors.add(:party_size, "大人數和小孩數的總和必須等於總人數")
    end
  end

  def customer_not_blacklisted
    return unless restaurant && customer_phone
    
    if Blacklist.blacklisted_phone?(restaurant, customer_phone)
      errors.add(:customer_phone, '此電話號碼已列入黑名單，無法進行訂位')
    end
  end

  def broadcast_status_change
    # 廣播訂位狀態變更（用於即時更新）
    # 這裡可以加入 Turbo Stream 廣播邏輯
  end

  # 清除可用性快取
  def clear_availability_cache
    return unless restaurant_id.present?
    
    # 清除當天和相關日期的快取
    target_date = reservation_datetime&.to_date || Date.current
    
    # 清除可用時段快取（清除當天的所有人數組合）
    (1..20).each do |party_size|
      (0..party_size).each do |children|
        adults = party_size - children
        cache_key = "available_slots:#{restaurant_id}:#{target_date}:#{party_size}:#{adults}:#{children}"
        Rails.cache.delete(cache_key)
      end
    end
    
    # 清除可用性狀態快取（包含所有人數組合）
    (1..20).each do |party_size|
      Rails.cache.delete("availability_status:#{restaurant_id}:#{Date.current}:#{party_size}:v3")
    end
    
    # 清除舊版本的快取鍵（向後相容）
    Rails.cache.delete("availability_status:#{restaurant_id}:#{Date.current}")
    Rails.cache.delete("availability_status:#{restaurant_id}:#{Date.current}:v2")
    
    Rails.logger.info "Cleared availability cache for restaurant #{restaurant_id} on #{target_date}"
  end
end
