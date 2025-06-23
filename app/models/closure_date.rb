class ClosureDate < ApplicationRecord
  # 1. 關聯定義
  belongs_to :restaurant

  # 2. 驗證規則
  validates :date, presence: true
  validates :closure_type, presence: true
  validates :weekday, presence: true, inclusion: { in: 0..6 }, if: :recurring?
  validate :end_time_after_start_time, if: -> { !all_day? && start_time && end_time }
  validate :future_date_for_new_records, on: :create
  validate :unique_weekly_closure, if: :recurring?

  # 3. 枚舉定義
  enum :closure_type, {
    regular: 0,      # 定期公休
    holiday: 1,      # 節假日
    maintenance: 2,  # 設備維修
    emergency: 3,    # 緊急狀況
    private_event: 4 # 私人活動
  }

  # 4. Scope 定義
  scope :for_date, ->(date) { where(date: date) }
  scope :for_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :recurring_closures, -> { where(recurring: true) }
  scope :one_time_closures, -> { where(recurring: false) }
  scope :by_type, ->(type) { where(closure_type: type) }
  scope :for_weekday, ->(weekday) { where(weekday: weekday) }
  scope :ordered, -> { order(:date, :start_time) }

  # 5. 回調函數
  before_validation :set_defaults
  before_validation :sanitize_inputs

  # 6. 實例方法
  def display_name
    case closure_type
    when 'regular'
      '定期公休'
    when 'holiday'
      '節假日'
    when 'maintenance'
      '設備維修'
    when 'emergency'
      '緊急狀況'
    when 'private_event'
      '私人活動'
    end
  end

  def formatted_date
    date.strftime('%Y年%m月%d日 (%A)')
  end

  def formatted_time_range
    return '全日' if all_day?
    return '' unless start_time && end_time

    "#{start_time.strftime('%H:%M')} - #{end_time.strftime('%H:%M')}"
  end

  def affects_time?(time)
    return true if all_day?
    return false unless start_time && end_time

    time.between?(start_time, end_time)
  end

  def self.closed_on_date?(restaurant_id, date)
    # 檢查特定日期的公休
    return true if exists?(restaurant_id: restaurant_id, date: date)

    # 檢查每週重複的公休
    weekday_number = date.wday # 使用 0-6 格式（週日到週六）

    recurring_closures.exists?(restaurant_id: restaurant_id, weekday: weekday_number)
  end

  def self.closed_during_time?(restaurant_id, datetime)
    closure = for_date(datetime.to_date)
      .where(restaurant_id: restaurant_id)
      .first

    return false unless closure

    closure.affects_time?(datetime.time_of_day)
  end

  # 檢查特定日期是否受每週重複公休影響
  def self.recurring_closure_on_date?(restaurant_id, date)
    weekday_number = date.wday # 使用 0-6 格式（週日到週六）
    recurring_closures.exists?(restaurant_id: restaurant_id, weekday: weekday_number)
  end

  # 獲取特定週幾的重複公休設定
  def self.weekly_closure_for_weekday(restaurant_id, weekday_number)
    recurring_closures.where(restaurant_id: restaurant_id, weekday: weekday_number).first
  end

  # 7. 私有方法
  private

  def set_defaults
    self.all_day = true if all_day.nil?
    self.recurring = false if recurring.nil?
    self.closure_type ||= 'regular'
  end

  def sanitize_inputs
    self.reason = reason&.strip
  end

  def end_time_after_start_time
    return unless start_time && end_time

    return unless end_time <= start_time

    errors.add(:end_time, '結束時間必須晚於開始時間')
  end

  def future_date_for_new_records
    return if recurring? # 重複性公休日不檢查
    return unless date

    return unless date < Date.current

    errors.add(:date, '公休日期不能是過去的日期')
  end

  def unique_weekly_closure
    return unless recurring? && weekday.present?

    # 檢查同一餐廳是否已經有相同週幾的重複公休日
    existing_closure = restaurant.closure_dates
      .where(recurring: true, weekday: weekday)
      .where.not(id: id) # 排除自己（用於更新時）
      .first

    return unless existing_closure

    weekday_names = %w[週日 週一 週二 週三 週四 週五 週六]
    weekday_name = weekday_names[weekday] if weekday.between?(0, 6)
    errors.add(:base, "#{weekday_name}已經設定為公休日")
  end
end
