class ShortUrl < ApplicationRecord
  # 1. 驗證規則
  validates :token, presence: true, uniqueness: true, length: { is: 8 }
  validates :original_url, presence: true
  validates :expires_at, presence: true
  validates :click_count, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # 2. Scope 定義
  scope :expired, -> { where(expires_at: ...Time.current) }
  scope :active, -> { where(expires_at: Time.current..) }
  scope :recent, -> { order(created_at: :desc) }
  scope :popular, -> { order(click_count: :desc) }

  # 3. 回調函數
  before_validation :set_defaults, on: :create

  # 4. 實例方法
  def expired?
    expires_at < Time.current
  end

  def active?
    !expired?
  end

  def short_url
    base_url = build_base_url
    protocol = Rails.env.production? ? 'https' : 'http'
    "#{protocol}://#{base_url}/s/#{token}"
  end

  def formatted_created_at
    created_at.strftime('%Y-%m-%d %H:%M:%S')
  end

  def formatted_expires_at
    expires_at.strftime('%Y-%m-%d %H:%M:%S')
  end

  def formatted_last_accessed_at
    return '從未訪問' if last_accessed_at.blank?

    last_accessed_at.strftime('%Y-%m-%d %H:%M:%S')
  end

  def time_until_expiry
    return 0 if expired?

    ((expires_at - Time.current) / 1.day).round(1)
  end

  private

  def set_defaults
    self.click_count ||= 0
    self.expires_at ||= 90.days.from_now
  end

  # 建構基礎網址（與 UrlShortenerService 保持一致）
  def build_base_url
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
      'localhost:3001'
    end
  end
end
