class SpecialReservationDate < ApplicationRecord
  # 1. 關聯定義
  belongs_to :restaurant

  # 2. 驗證規則
  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }
  validates :start_date, :end_date, presence: true
  
  # 營業模式驗證
  validates :operation_mode, presence: true, inclusion: { in: %w[closed custom_hours] }
  
  # 當選擇自訂時段時，桌位使用時間為必填
  validates :table_usage_minutes, presence: true, 
            numericality: { greater_than: 0 }, 
            if: :custom_hours?
  
  # 日期邏輯驗證
  validate :end_date_after_start_date
  validate :dates_not_in_past
  validate :no_overlapping_dates_for_restaurant
  validate :custom_periods_format, if: :custom_hours?

  # 3. Scope 定義
  scope :active, -> { where(active: true) }
  scope :for_restaurant, ->(restaurant) { where(restaurant: restaurant) }
  scope :for_date, ->(date) { where(start_date: ..date, end_date: date..) }
  scope :ordered_by_date, -> { order(created_at: :desc) }

  # 4. Enum 定義
  enum operation_mode: {
    closed: 'closed',           # 整日不開放
    custom_hours: 'custom_hours' # 自訂時段開放
  }

  # 5. 回調函數
  before_validation :set_defaults
  before_validation :sanitize_inputs

  # 6. 常數定義
  INTERVAL_OPTIONS = [15, 30, 60, 90, 120, 150, 180, 210, 240].freeze

  # 7. 實例方法
  def display_name
    name
  end

  def date_range
    "#{start_date.strftime('%Y-%m-%d')} ~ #{end_date.strftime('%Y-%m-%d')}"
  end
  
  # 顯示日期範圍 (中文格式)
  def date_range_display
    if start_date == end_date
      start_date.strftime('%Y年%m月%d日')
    else
      "#{start_date.strftime('%Y年%m月%d日')} - #{end_date.strftime('%Y年%m月%d日')}"
    end
  end
  
  # 檢查是否為單日設定
  def single_date?
    start_date == end_date
  end
  
  # 取得影響的日期陣列
  def affected_dates
    (start_date..end_date).to_a
  end

  def covers_date?(date)
    date = date.to_date if date.respond_to?(:to_date)
    start_date <= date && date <= end_date
  end

  def duration_days
    (end_date - start_date).to_i + 1
  end

  # 檢查指定時間是否在自訂時段內
  def time_available?(time_string)
    return false unless custom_hours?
    return false if custom_periods.blank?

    generate_available_time_slots.include?(time_string)
  end

  # 根據自訂時段生成可預約時間
  def generate_available_time_slots
    return [] unless custom_hours? && custom_periods.present?

    time_slots = []
    
    custom_periods.each do |period|
      start_time = Time.parse(period['start_time'])
      end_time = Time.parse(period['end_time'])
      interval = period['interval_minutes'].to_i
      
      # 確保間隔在允許範圍內
      next unless INTERVAL_OPTIONS.include?(interval)
      
      current_time = start_time
      # 迴圈條件改為 <，確保最後一個時段的開始時間加上用餐時間不會超過結束時間
      while current_time < end_time
        time_slots << current_time.strftime('%H:%M')
        current_time += interval.minutes
      end
    end
    
    time_slots.uniq.sort
  end

  # 8. 私有方法
  private

  def set_defaults
    self.active = true if active.nil?
    self.operation_mode ||= 'closed'
    self.custom_periods ||= []
  end

  def sanitize_inputs
    self.name = name&.strip
    self.description = description&.strip
  end

  def end_date_after_start_date
    return unless start_date && end_date
    
    if end_date < start_date
      errors.add(:end_date, '結束日期不能早於開始日期')
    end
  end

  def dates_not_in_past
    return unless start_date
    
    if start_date < Date.current
      errors.add(:start_date, '開始日期不能是過去的日期')
    end
  end

  def no_overlapping_dates_for_restaurant
    return unless restaurant && start_date && end_date
    
    overlapping = restaurant.special_reservation_dates
      .where.not(id: id)
      .where(active: true)
      .where(
        "(start_date <= ? AND end_date >= ?) OR " \
        "(start_date <= ? AND end_date >= ?) OR " \
        "(start_date >= ? AND end_date <= ?)",
        start_date, start_date,
        end_date, end_date,
        start_date, end_date
      )
    
    if overlapping.exists?
      conflicting_dates = overlapping.pluck(:name, :start_date, :end_date)
        .map { |name, start_d, end_d| "#{name} (#{start_d} ~ #{end_d})" }
        .join(', ')
      errors.add(:base, "日期範圍與現有特殊訂位日重疊: #{conflicting_dates}")
    end
  end

  def custom_periods_format
    return if custom_periods.blank?
    
    unless custom_periods.is_a?(Array)
      errors.add(:custom_periods, '自訂時段格式錯誤')
      return
    end
    
    custom_periods.each_with_index do |period, index|
      unless period.is_a?(Hash)
        errors.add(:custom_periods, "時段 #{index + 1} 格式錯誤")
        next
      end
      
      %w[start_time end_time interval_minutes].each do |key|
        unless period.key?(key)
          errors.add(:custom_periods, "時段 #{index + 1} 缺少 #{key}")
        end
      end
      
      if period['interval_minutes'].present?
        interval = period['interval_minutes'].to_i
        unless INTERVAL_OPTIONS.include?(interval)
          errors.add(:custom_periods, "時段 #{index + 1} 的間隔時間必須是 #{INTERVAL_OPTIONS.join(', ')} 分鐘之一")
        end
      end
      
      if period['start_time'].present? && period['end_time'].present?
        begin
          start_time = Time.parse(period['start_time'])
          end_time = Time.parse(period['end_time'])
          
          if start_time >= end_time
            errors.add(:custom_periods, "時段 #{index + 1} 的結束時間必須晚於開始時間")
          end
        rescue ArgumentError
          errors.add(:custom_periods, "時段 #{index + 1} 的時間格式錯誤")
        end
      end
    end
  end
end