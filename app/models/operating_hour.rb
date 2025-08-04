class OperatingHour < ApplicationRecord
  # 1. 關聯定義
  belongs_to :restaurant

  # 2. 星期枚舉定義
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
  validates :weekday, presence: true, inclusion: { in: 0..6 }
  validates :open_time, :close_time, presence: true
  validates :sort_order, presence: true, numericality: { greater_than: 0 }
  validate :close_time_after_open_time
  validate :no_time_overlap_within_day

  # 4. Scope 定義
  scope :for_weekday, ->(weekday) { where(weekday: weekday) }
  scope :ordered, -> { order(:weekday, :sort_order, :open_time) }
  scope :for_restaurant_and_weekday, lambda { |restaurant_id, weekday|
    where(restaurant_id: restaurant_id, weekday: weekday)
  }

  # Ransack 搜索屬性白名單
  def self.ransackable_attributes(_auth_object = nil)
    %w[
      close_time
      created_at
      id
      open_time
      restaurant_id
      updated_at
      weekday
    ]
  end

  # Ransack 搜索關聯白名單
  def self.ransackable_associations(_auth_object = nil)
    %w[restaurant]
  end

  after_destroy :clear_restaurant_cache
  # 5. 回調方法
  after_save :clear_restaurant_cache

  # 6. 實例方法
  def chinese_weekday
    CHINESE_WEEKDAYS[weekday]
  end

  def formatted_time_range
    "#{local_open_time.strftime('%H:%M')} - #{local_close_time.strftime('%H:%M')}"
  end

  def local_open_time
    open_time.in_time_zone
  end

  def local_close_time
    close_time.in_time_zone
  end

  def duration_minutes
    ((close_time - open_time) / 1.minute).to_i
  end

  def covers_time?(time)
    time_only = time.is_a?(Time) ? time.strftime('%H:%M:%S') : time.to_s
    open_time_str = open_time.strftime('%H:%M:%S')
    close_time_str = close_time.strftime('%H:%M:%S')

    time_only >= open_time_str && time_only <= close_time_str
  end

  # 7. 私有方法
  private

  def clear_restaurant_cache
    restaurant&.clear_operating_hours_cache
  end

  def close_time_after_open_time
    return unless open_time && close_time

    return unless close_time <= open_time

    errors.add(:close_time, '結束時間必須晚於開始時間')
  end

  def no_time_overlap_within_day
    return unless restaurant_id && weekday && open_time && close_time

    # 查找同一餐廳同一天的其他時段
    other_periods = OperatingHour.for_restaurant_and_weekday(restaurant_id, weekday)
      .where.not(id: id) # 排除自己

    other_periods.each do |period|
      # 檢查時間重疊
      if time_ranges_overlap?(open_time, close_time, period.open_time, period.close_time)
        errors.add(:base, "時段與「#{period.period_name}」的時間重疊")
      end
    end
  end

  def time_ranges_overlap?(start1, end1, start2, end2)
    start1 < end2 && start2 < end1
  end
end
