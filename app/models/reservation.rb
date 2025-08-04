class Reservation < ApplicationRecord
  # 控制是否跳過黑名單驗證（用於前台統一處理錯誤訊息）
  attr_accessor :skip_blacklist_validation

  # 啟用樂觀鎖定
  self.locking_column = :lock_version

  # 1. 關聯定義（放在最前面）
  belongs_to :restaurant
  belongs_to :table, optional: true, class_name: 'RestaurantTable'
  belongs_to :reservation_period, optional: true
  has_one :table_combination, dependent: :destroy
  has_many :sms_logs, dependent: :destroy

  # 向後相容性方法
  alias restaurant_table table
  alias restaurant_table= table=

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
  validate :customer_not_blacklisted, on: :create, unless: :skip_blacklist_validation
  validate :table_required_for_admin_creation
  validate :check_table_availability_conflict, on: :create
  validate :check_time_slot_overlap, on: :create
  validate :check_customer_phone_duplicate, on: :create

  # 3. Scope 定義
  scope :active, -> { where.not(status: %w[cancelled no_show]) }
  scope :admin_override, -> { where(admin_override: true) }
  scope :normal_bookings, -> { where(admin_override: false) }
  scope :for_date, ->(date) { where(reservation_datetime: date.all_day) }
  scope :for_time_range, ->(start_time, end_time) { where(reservation_datetime: start_time..end_time) }
  scope :with_adults, ->(count) { where(adults_count: count) }
  scope :with_children, ->(count) { where(children_count: count) }
  scope :large_party, ->(size) { where(party_size: size..) }
  scope :confirmed, -> { where(status: 'confirmed') }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_datetime, -> { order(:reservation_datetime) }

  # 4. 枚舉定義
  enum :status, {
    pending: 'pending',
    confirmed: 'confirmed',
    cancelled: 'cancelled',
    no_show: 'no_show'
  }

  # Ransack 搜索屬性白名單
  def self.ransackable_attributes(_auth_object = nil)
    %w[
      adults_count reservation_period_id children_count created_at
      customer_email customer_name customer_phone id party_size
      reservation_datetime restaurant_id special_requests status
      table_id updated_at cancelled_by cancelled_at cancellation_reason
      cancellation_method cancellation_token
    ]
  end

  # Ransack 搜索關聯白名單
  def self.ransackable_associations(_auth_object = nil)
    %w[reservation_period restaurant table table_combination]
  end

  # 5. 回調函數
  before_validation :sanitize_inputs
  before_create :generate_cancellation_token
  after_create_commit :send_sms_notification_on_create
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?
  after_update_commit :send_sms_notification, if: :saved_change_to_status?

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

  def can_cancel_by_customer?
    # 客戶可以取消的條件：
    # 1. 訂位狀態為 pending 或 confirmed
    # 2. 還沒有到訂位時間
    return false unless can_cancel?
    return false if is_past?

    # 簡化邏輯：只要還沒到時間就可以取消
    true
  end

  def cancellation_url
    return nil if cancellation_token.blank?

    Rails.application.routes.url_helpers.restaurant_reservation_cancel_url(
      restaurant.slug,
      cancellation_token,
      host: build_url_host
    )
  end

  def short_cancellation_url
    return nil if cancellation_token.blank?

    original_url = cancellation_url
    return nil if original_url.blank?

    # 使用 URL 縮短服務
    shortener = UrlShortenerService.new
    shortener.shorten_url(original_url)
  rescue StandardError => e
    Rails.logger.error "Failed to generate short cancellation URL for reservation #{id}: #{e.message}"
    cancellation_url # 失敗時回傳原始網址
  end

  def cancellation_deadline
    # 簡化：不設定特定的取消截止時間，只要還沒到訂位時間就可以取消
    reservation_datetime
  end

  def cancel_by_customer!(reason = nil)
    return false unless can_cancel_by_customer?

    transaction do
      self.status = :cancelled
      self.cancelled_by = 'customer'
      self.cancelled_at = Time.current
      self.cancellation_reason = reason if reason.present?
      self.cancellation_method = 'online_self_service'

      # 保留舊的 notes 記錄方式作為備份
      old_notes = notes
      cancellation_info = [
        "客戶取消於 #{cancelled_at.strftime('%Y/%m/%d %H:%M')}",
        reason.present? ? "原因：#{reason}" : nil
      ].compact.join(' | ')

      self.notes = [old_notes, cancellation_info].compact.join(' | ')

      save!

      # 清除桌位分配
      if table_combination.present?
        table_combination.destroy!
      else
        self.table = nil
        save!
      end

      # 通知餐廳（可以發送 email 或其他通知）
      # NotificationService.new.notify_restaurant_of_cancellation(self)
    end

    true
  rescue StandardError => e
    Rails.logger.error "Failed to cancel reservation #{id}: #{e.message}"
    false
  end

  def cancel_by_admin!(user, reason = nil)
    return false unless can_cancel?

    transaction do
      self.status = :cancelled
      self.cancelled_by = "admin:#{user.name}"
      self.cancelled_at = Time.current
      self.cancellation_reason = reason if reason.present?
      self.cancellation_method = 'admin_interface'

      # 保留舊的 notes 記錄方式作為備份
      old_notes = notes
      cancellation_info = [
        "管理員#{user.name}取消於 #{cancelled_at.strftime('%Y/%m/%d %H:%M')}",
        reason.present? ? "原因：#{reason}" : nil
      ].compact.join(' | ')

      self.notes = [old_notes, cancellation_info].compact.join(' | ')

      save!

      # 清除桌位分配
      if table_combination.present?
        table_combination.destroy!
      else
        self.table = nil
        save!
      end
    end

    true
  rescue StandardError => e
    Rails.logger.error "Failed to cancel reservation #{id} by admin: #{e.message}"
    false
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
    children_count.positive?
  end

  # 檢查是否為商務聚餐
  # def business_meeting?
  #   return false if special_requests.blank?

  #   business_keywords = %w[商務 會議 business meeting corporate]
  #   business_keywords.any? { |keyword| special_requests.downcase.include?(keyword) }
  # end

  # 計算總用餐時間（包含緩衝時間）
  def total_duration_minutes
    return nil if restaurant&.policy&.unlimited_dining_time? # 無限時模式回傳 nil

    restaurant&.dining_duration_with_buffer || 135 # 預設 120 分鐘 + 15 分鐘緩衝
  end

  # 計算佔用時間範圍
  def occupation_time_range
    return nil if restaurant&.policy&.unlimited_dining_time? # 無限時模式沒有結束時間

    duration = total_duration_minutes
    return nil unless duration # 如果沒有設定時間，回傳 nil

    end_time = reservation_datetime + duration.minutes
    reservation_datetime..end_time
  end

  # 快取失效回調
  after_create :clear_availability_cache
  after_update :clear_availability_cache, if: :saved_change_to_status?
  after_destroy :clear_availability_cache

  # 管理員強制建立相關方法
  def admin_override?
    admin_override
  end

  def forced_booking?
    admin_override
  end

  def admin_created?
    admin_override
  end

  def normal_booking?
    !admin_override
  end

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

    policy = restaurant&.reservation_policy
    min_advance_hours = policy&.minimum_advance_hours || 1
    max_advance_days = policy&.advance_booking_days || 30

    min_datetime = Time.current + min_advance_hours.hours
    max_datetime = Date.current + max_advance_days.days

    if reservation_datetime < min_datetime
      errors.add(:reservation_datetime, "訂位時間必須至少提前 #{min_advance_hours} 小時")
    elsif reservation_datetime.to_date > max_datetime
      errors.add(:reservation_datetime, "最多只能提前 #{max_advance_days} 天預約")
    end
  end

  def party_size_within_restaurant_limits
    return unless restaurant && party_size

    policy = restaurant.reservation_policy
    min_party_size = policy&.min_party_size || 1
    max_party_size = policy&.max_party_size || 12

    if party_size < min_party_size
      errors.add(:party_size, "人數不能少於 #{min_party_size} 人")
    elsif party_size > max_party_size
      errors.add(:party_size, "人數不能超過 #{max_party_size} 人")
    end
  end

  def party_size_matches_adults_and_children
    return unless adults_count && children_count && party_size

    return unless adults_count + children_count != party_size

    errors.add(:party_size, '大人數和小孩數的總和必須等於總人數')
  end

  def customer_not_blacklisted
    return unless restaurant && customer_phone

    return unless Blacklist.blacklisted_phone?(restaurant, customer_phone)

    # 為了避免暴露黑名單狀態，使用通用錯誤訊息
    errors.add(:base, '訂位失敗，請聯繫餐廳')
  end

  def table_required_for_admin_creation
    # 只有在後台建立且不是編輯時才檢查桌位必填
    return unless new_record? && admin_override?

    return if table_id.present?

    errors.add(:table_id, '後台建立訂位時必須指定桌位')
  end

  def broadcast_status_change
    # 廣播訂位狀態變更（用於即時更新）
    # 這裡可以加入 Turbo Stream 廣播邏輯
  end

  # 清除可用性快取（智能版本）
  def clear_availability_cache
    return if restaurant_id.blank?

    target_date = reservation_datetime&.to_date || Date.current

    # 計算餐廳設定的時間戳（用於建構正確的 cache key）
    restaurant_updated_at = [restaurant.updated_at,
                             restaurant.reservation_policy&.updated_at,
                             restaurant.reservation_periods.maximum(:updated_at)].compact.max

    # 根據訂位影響範圍，智能清除 cache
    affected_party_sizes = calculate_affected_party_sizes

    affected_party_sizes.each do |party_size|
      # 使用正確的 cache key 格式清除可用性狀態
      availability_key = "availability_status:#{restaurant_id}:#{target_date}:#{party_size}:#{restaurant_updated_at.to_i}:v4"
      Rails.cache.delete(availability_key)

      # 清除可用時段快取（只清除相關組合）
      (0..party_size).each do |children|
        adults = party_size - children
        slots_key = "available_slots:#{restaurant_id}:#{target_date}:#{party_size}:#{adults}:#{children}:#{restaurant_updated_at.to_i}:v2"
        Rails.cache.delete(slots_key)
      end
    end

    Rails.logger.info "Cleared availability cache for restaurant #{restaurant_id} on #{target_date} for party sizes: #{affected_party_sizes}"
  end

  # 計算受訂位影響的人數範圍
  def calculate_affected_party_sizes
    base_party_size = party_size || 2

    # 獲取餐廳的最大人數限制
    max_allowed = restaurant.policy&.max_party_size || 12

    # 影響範圍：訂位人數的 ±2，最小1人，最大根據餐廳政策
    range_start = [base_party_size - 2, 1].max
    range_end = [base_party_size + 2, max_allowed].min

    (range_start..range_end).to_a
  end

  def generate_cancellation_token
    self.cancellation_token = SecureRandom.hex(16)
  end

  # 樂觀鎖併發衝突檢測驗證
  def check_table_availability_conflict
    return unless table_id.present? && reservation_datetime.present?

    # 計算用餐時間範圍
    duration_minutes = restaurant.dining_duration_minutes || 120
    new_start = reservation_datetime
    new_end = reservation_datetime + duration_minutes.minutes

    # 建立基本查詢條件
    query = Reservation.where(
      restaurant_id: restaurant_id,
      table_id: table_id,
      status: %w[confirmed pending]
    ).where(
      reservation_datetime: (new_start - duration_minutes.minutes)..(new_end)
    )

    # 如果是更新現有記錄，排除自己
    query = query.where.not(id: id) if persisted?

    potentially_conflicting = query

    # 在 Ruby 中進行精確的時間重疊檢測
    conflicting = potentially_conflicting.any? do |reservation|
      existing_start = reservation.reservation_datetime
      existing_end = existing_start + duration_minutes.minutes

      # 檢查兩個時間區間是否重疊
      new_start < existing_end && new_end > existing_start
    end

    return unless conflicting

    errors.add(:reservation_datetime, '該桌位在此時段已被預訂')
  end

  def check_time_slot_overlap
    return unless reservation_datetime.present?

    # 建立基本查詢條件
    query = Reservation.where(
      restaurant_id: restaurant_id,
      reservation_datetime: reservation_datetime,
      status: %w[confirmed pending]
    )

    # 如果是更新現有記錄，排除自己
    query = query.where.not(id: id) if persisted?

    same_time_reservations = query

    total_party_size = same_time_reservations.sum(:party_size) + (party_size || 0)
    restaurant_capacity = restaurant.total_capacity

    return unless total_party_size > restaurant_capacity

    errors.add(:reservation_datetime, '該時段人數已滿，請選擇其他時間')
  end

  def check_customer_phone_duplicate
    return unless customer_phone.present? && reservation_datetime.present?

    # 建立基本查詢條件
    query = Reservation.where(
      restaurant_id: restaurant_id,
      customer_phone: customer_phone,
      reservation_datetime: reservation_datetime,
      status: %w[confirmed pending]
    )

    # 如果是更新現有記錄，排除自己
    query = query.where.not(id: id) if persisted?

    duplicate = query.exists?

    return unless duplicate

    errors.add(:customer_phone, '此手機號碼已在相同時段重複預訂')
  end

  def send_sms_notification_on_create
    # 只有在簡訊服務啟用時才發送通知
    # return unless Rails.env.production? || ENV['SMS_SERVICE_ENABLED'] == 'true'
    return if customer_phone.blank?

    # 新建訂位時，如果狀態是 confirmed，發送確認簡訊
    if confirmed?
      SmsNotificationJob.perform_now(id, 'reservation_confirmation')
      Rails.logger.info "Queued confirmation SMS for new reservation #{id}"
    end
  rescue StandardError => e
    Rails.logger.error "Failed to queue SMS notification for new reservation #{id}: #{e.message}"
  end

  def send_sms_notification
    # 只有在簡訊服務啟用時才發送通知
    return unless Rails.env.production? || ENV['SMS_SERVICE_ENABLED'] == 'true'
    return if customer_phone.blank?

    # 根據狀態變更發送對應的簡訊通知
    case status
    when 'confirmed'
      # 訂位確認通知（只在狀態變更時發送）
      SmsNotificationJob.perform_later(id, 'reservation_confirmation')
      Rails.logger.info "Queued confirmation SMS for reservation #{id} status change"
    when 'cancelled'
      # 訂位取消通知
      cancellation_reason = self.cancellation_reason || '無特殊原因'
      SmsNotificationJob.perform_later(id, 'reservation_cancellation', { cancellation_reason: cancellation_reason })
      Rails.logger.info "Queued cancellation SMS for reservation #{id}"
    end
  rescue StandardError => e
    Rails.logger.error "Failed to queue SMS notification for reservation #{id}: #{e.message}"
  end

  # 建構網址主機（與短網址服務保持一致）
  def build_url_host
    if Rails.application.config.action_mailer.default_url_options
      host = Rails.application.config.action_mailer.default_url_options[:host]
      port = Rails.application.config.action_mailer.default_url_options[:port]

      # 如果有明確設定端口號，或者在開發環境且 host 是 localhost，則加上端口號
      if port
        "#{host}:#{port}"
      elsif Rails.env.development? && host == 'localhost'
        "#{host}:3000"
      else
        host
      end
    else
      'localhost:3000'
    end
  end
end
