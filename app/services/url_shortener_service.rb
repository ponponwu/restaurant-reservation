class UrlShortenerService
  include Rails.application.routes.url_helpers

  BASE62_ALPHABET = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'.freeze
  SHORT_URL_LENGTH = 8  # 增加到8字元提高唯一性
  TIMESTAMP_LENGTH = 4  # 時間戳部分長度
  RANDOM_LENGTH = 4     # 隨機部分長度
  EXPIRY_DAYS = 90      # 短網址90天後過期
  MAX_RETRY_ATTEMPTS = 10 # 最大重試次數

  # 建立短網址
  def shorten_url(original_url, expires_at: EXPIRY_DAYS.days.from_now)
    return original_url if original_url.blank?

    # 檢查是否已經存在短網址
    existing_short_url = ShortUrl.find_by(original_url: original_url, expires_at: expires_at..)
    if existing_short_url
      short_url = build_short_url(existing_short_url.token)
      return short_url || original_url
    end

    # 產生唯一的短網址 token
    token = generate_unique_token

    # 建立短網址記錄
    ShortUrl.create!(
      token: token,
      original_url: original_url,
      expires_at: expires_at
    )

    # 建構短網址，如果失敗則返回原始網址
    short_url = build_short_url(token)
    short_url || original_url
  rescue ActiveRecord::RecordNotUnique => e
    # 處理並發情況下的唯一性約束違反
    Rails.logger.warn "Short URL token collision detected, retrying: #{e.message}"
    # 重新嘗試生成（遞迴調用，但有重試限制保護）
    shorten_url(original_url, expires_at: expires_at)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to create short URL: #{e.message}"
    original_url # 如果失敗就返回原始網址
  rescue StandardError => e
    Rails.logger.error "Unexpected error creating short URL: #{e.message}"
    original_url # 如果失敗就返回原始網址
  end

  # 解析短網址
  def resolve_url(token)
    short_url = ShortUrl.find_by(token: token)

    return nil unless short_url
    return nil if short_url.expired?

    # 更新點擊次數和最後訪問時間
    short_url.increment!(:click_count)
    short_url.update!(last_accessed_at: Time.current)

    short_url.original_url
  end

  # 批量清理過期的短網址
  def self.cleanup_expired_urls
    expired_count = ShortUrl.expired.delete_all
    Rails.logger.info "Cleaned up #{expired_count} expired short URLs"
    expired_count
  end

  # 獲取短網址使用統計
  def self.usage_statistics
    total_urls = ShortUrl.count
    active_urls = ShortUrl.active.count
    expired_urls = ShortUrl.expired.count
    total_clicks = ShortUrl.sum(:click_count)

    # 計算理論容量使用率
    theoretical_capacity = 62**8 # 62^8 個可能的組合
    usage_percentage = (total_urls.to_f / theoretical_capacity * 100).round(10)

    {
      total_urls: total_urls,
      active_urls: active_urls,
      expired_urls: expired_urls,
      total_clicks: total_clicks,
      usage_percentage: usage_percentage,
      theoretical_capacity: theoretical_capacity,
      top_clicked_urls: ShortUrl.order(click_count: :desc).limit(10).pluck(:token, :click_count),
      recent_urls: ShortUrl.order(created_at: :desc).limit(10).pluck(:token, :created_at)
    }
  end

  # 檢查系統健康狀態
  def self.health_check
    stats = usage_statistics
    warnings = []

    # 檢查使用率警告
    warnings << "High usage: #{stats[:usage_percentage]}%" if stats[:usage_percentage] > 0.01
    warnings << "Many expired URLs: #{stats[:expired_urls]}" if stats[:expired_urls] > 10000

    {
      status: warnings.empty? ? 'healthy' : 'warning',
      warnings: warnings,
      statistics: stats
    }
  end

  private

  # 產生唯一的短網址 token（帶重試限制）
  def generate_unique_token
    attempts = 0

    loop do
      attempts += 1
      token = generate_token

      # 檢查唯一性
      unless ShortUrl.exists?(token: token)
        # 記錄重試統計（如果有重試）
        Rails.logger.info "Short URL token generated after #{attempts} attempts" if attempts > 1
        return token
      end

      # 達到最大重試次數時拋出異常
      if attempts >= MAX_RETRY_ATTEMPTS
        Rails.logger.error "Failed to generate unique short URL token after #{MAX_RETRY_ATTEMPTS} attempts"
        raise "Unable to generate unique token after #{MAX_RETRY_ATTEMPTS} attempts"
      end
    end
  end

  # 產生混合時間戳的 token（提高唯一性）
  def generate_token
    # 時間戳部分：使用毫秒級時間戳的後4位轉為Base62
    timestamp_ms = (Time.current.to_f * 1000).to_i
    timestamp_part = encode_base62(timestamp_ms).last(TIMESTAMP_LENGTH).rjust(TIMESTAMP_LENGTH, '0')

    # 隨機部分：純隨機字符
    random_part = Array.new(RANDOM_LENGTH) { BASE62_ALPHABET.chars.sample }.join

    # 組合：時間戳 + 隨機 = 8字符
    "#{timestamp_part}#{random_part}"
  end

  # Base62 編碼（將數字轉為Base62字符串）
  def encode_base62(number)
    return BASE62_ALPHABET[0] if number.zero?

    result = ''
    while number.positive?
      result = BASE62_ALPHABET[number % 62] + result
      number /= 62
    end
    result
  end

  # 建構完整的短網址
  def build_short_url(token)
    # 獲取正確的 host 配置
    host = get_configured_host
    protocol = Rails.env.production? ? 'https' : 'http'

    short_url_redirect_url(
      token: token,
      protocol: protocol,
      host: host
    )
  rescue StandardError => e
    Rails.logger.error "Failed to build short URL: #{e.message}"
    # 如果無法生成短網址，返回 nil，讓調用方使用原始網址
    nil
  end

  # 獲取配置的主機地址
  def get_configured_host
    # 1. 優先使用 action_mailer 配置
    if Rails.application.config.action_mailer.default_url_options
      mailer_config = Rails.application.config.action_mailer.default_url_options
      host = mailer_config[:host]
      port = mailer_config[:port]

      # 組合 host 和 port
      return "#{host}:#{port}" if port && !Rails.env.production?

      return host

    end

    # 2. 根據環境使用預設值
    if Rails.env.production?
      # 生產環境應該要有正確的 host 配置
      Rails.logger.warn 'Production environment missing host configuration for short URLs'
      'localhost'
    elsif Rails.env.development?
      'localhost:3000'
    else
      'localhost'
    end
  end
end
