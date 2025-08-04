class SmsLog < ApplicationRecord
  # 1. 關聯定義
  belongs_to :reservation

  # 2. 驗證規則
  validates :phone_number, presence: true
  validates :message_type, presence: true
  validates :content, presence: true
  validates :status, presence: true

  # 3. 枚舉定義
  enum :status, {
    pending: 'pending',
    sent: 'sent',
    failed: 'failed',
    error: 'error'
  }

  enum :message_type, {
    reservation_confirmation: 'reservation_confirmation',
    dining_reminder: 'dining_reminder',
    reservation_cancellation: 'reservation_cancellation'
  }

  # 4. Scope 定義
  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status: 'sent') }
  scope :failed, -> { where(status: %w[failed error]) }
  scope :for_phone, ->(phone) { where(phone_number: phone) }
  scope :for_date, ->(date) { where(created_at: date.all_day) }

  # 5. 實例方法
  def success?
    sent?
  end

  def failure?
    failed? || error?
  end

  def formatted_created_at
    created_at.strftime('%Y-%m-%d %H:%M:%S')
  end

  def message_type_name
    case message_type
    when 'reservation_confirmation'
      '訂位確認'
    when 'dining_reminder'
      '用餐提醒'
    when 'reservation_cancellation'
      '訂位取消'
    else
      message_type
    end
  end

  def status_name
    case status
    when 'pending'
      '待發送'
    when 'sent'
      '已發送'
    when 'failed'
      '發送失敗'
    when 'error'
      '系統錯誤'
    else
      status
    end
  end
end
