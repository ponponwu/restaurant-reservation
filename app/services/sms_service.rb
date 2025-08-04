class SmsService
  require 'net/http'
  require 'json'

  def initialize
    @api_url = ENV.fetch('SMS_SERVICE_URL', nil)
    # @api_key = ENV.fetch('SMS_SERVICE_API_KEY', nil)
    # @username = ENV.fetch('SMS_SERVICE_USERNAME', nil)
    # @password = ENV.fetch('SMS_SERVICE_PASSWORD', nil)
    @from = ENV['SMS_SERVICE_FROM'] || '餐廳訂位系統'
    # 開發環境預設啟用（用於測試），生產環境需要明確設定
    @enabled = Rails.env.development? || ENV['SMS_SERVICE_ENABLED'] == 'true'
    @timeout = ENV['SMS_SERVICE_TIMEOUT']&.to_i || 30
  end

  # 發送訂位確認簡訊
  def send_reservation_confirmation(reservation)
    return { success: false, error: 'SMS service disabled' } unless @enabled

    message = build_confirmation_message(reservation)
    send_sms(
      phone: reservation.customer_phone,
      message: message,
      reservation: reservation,
      message_type: 'reservation_confirmation'
    )
  end

  # 發送用餐提醒簡訊
  def send_dining_reminder(reservation)
    return { success: false, error: 'SMS service disabled' } unless @enabled

    message = build_reminder_message(reservation)
    send_sms(
      phone: reservation.customer_phone,
      message: message,
      reservation: reservation,
      message_type: 'dining_reminder'
    )
  end

  # 發送訂位取消通知
  def send_reservation_cancellation(reservation, reason = nil)
    return { success: false, error: 'SMS service disabled' } unless @enabled

    message = build_cancellation_message(reservation, reason)
    send_sms(
      phone: reservation.customer_phone,
      message: message,
      reservation: reservation,
      message_type: 'reservation_cancellation'
    )
  end

  private

  # 建立訂位確認訊息 (70字以內)
  def build_confirmation_message(reservation)
    restaurant = reservation.restaurant

    # 優先使用短網址，失敗時使用原始網址
    short_url = reservation.short_cancellation_url
    cancel_url = short_url || reservation.cancellation_url

    # 格式化日期和星期
    date = reservation.reservation_datetime.strftime('%m/%d')
    weekday = format_weekday(reservation.reservation_datetime.wday)
    time = reservation.reservation_datetime.strftime('%H:%M')

    # 精簡訊息模板：您已預約【餐廳名】07/17（四）12:00，1 位。訂位資訊：短網址
    message = "您已預約【#{restaurant.name}】#{date}（#{weekday}）#{time}，#{reservation.party_size} 位。"

    if cancel_url.present?
      message += "訂位資訊：#{cancel_url}"
      # 記錄是否使用了短網址
      Rails.logger.info "SMS message using #{short_url.present? ? 'short URL' : 'original URL'}: #{cancel_url}"
    end

    message
  end

  # 格式化星期顯示
  def format_weekday(wday)
    weekdays = %w[日 一 二 三 四 五 六]
    weekdays[wday]
  end

  # 建立用餐提醒訊息 (簡潔版本，適合簡訊)
  def build_reminder_message(reservation)
    restaurant = reservation.restaurant

    # 格式化日期和星期
    date = reservation.reservation_datetime.strftime('%m/%d')
    weekday = format_weekday(reservation.reservation_datetime.wday)
    time = reservation.formatted_time

    # 簡潔訊息格式：【餐廳名】明日用餐提醒 07/17（四）12:00，1位，桌號A1。
    message = "【#{restaurant.name}】明日用餐提醒 #{date}（#{weekday}）#{time}，#{reservation.party_size}位"
    short_url = reservation.short_cancellation_url

    if short_url.present?
      message += "訂位資訊：#{short_url}"
      # 記錄是否使用了短網址
      Rails.logger.info "SMS message using #{short_url.present? ? 'short URL' : 'original URL'}: #{short_url}"
    end

    message += '。'

    # # 只在有餐廳電話時添加聯絡資訊
    # if restaurant.phone.present?
    #   message += "聯絡電話：#{restaurant.phone}"
    # end

    message
  end

  # 建立取消訊息 (簡潔版本，適合簡訊)
  def build_cancellation_message(reservation, reason = nil)
    restaurant = reservation.restaurant

    # 格式化日期和星期
    date = reservation.reservation_datetime.strftime('%m/%d')
    weekday = format_weekday(reservation.reservation_datetime.wday)
    time = reservation.formatted_time

    # 簡潔訊息格式：【餐廳名】訂位已取消 07/17（四）12:00，1位。
    message = "【#{restaurant.name}】訂位已取消 #{date}（#{weekday}）#{time}，#{reservation.party_size}位"

    # 加上取消原因（如果有）
    message += "，原因：#{reason}" if reason.present? && reason != '無特殊原因'

    message += '。'

    # 加上餐廳聯絡電話
    message += "如需重新預約：#{restaurant.phone}" if restaurant.phone.present?

    message
  end

  # 發送簡訊的核心方法
  def send_sms(phone:, message:, reservation:, message_type:)
    # 驗證必要參數
    return { success: false, error: 'Missing required parameters' } if phone.blank? || message.blank?

    # 記錄發送請求
    sms_log = SmsLog.create!(
      reservation: reservation,
      phone_number: phone,
      message_type: message_type,
      content: message,
      status: 'pending'
    )

    begin
      # 發送 HTTP 請求到自架簡訊服務
      response = send_http_request(phone, message)

      # 更新發送狀態
      if response_successful?(response)
        sms_log.update!(
          status: 'sent',
          response_data: response.body
        )
        Rails.logger.info "SMS sent successfully to #{phone} for reservation #{reservation.id}"
        { success: true, sms_log: sms_log }
      else
        sms_log.update!(
          status: 'failed',
          response_data: response.body
        )
        Rails.logger.error "SMS sending failed to #{phone}: #{response.body}"
        { success: false, error: "SMS sending failed: #{response.code}", sms_log: sms_log }
      end
    rescue StandardError => e
      sms_log.update!(
        status: 'error',
        response_data: e.message
      )
      Rails.logger.error "SMS sending error to #{phone}: #{e.message}"
      { success: false, error: e.message, sms_log: sms_log }
    end
  end

  # 發送 HTTP 請求到簡訊服務
  def send_http_request(phone, message)
    return mock_response if Rails.env.test?

    # 開發環境使用詳細日誌模擬
    return development_mock_response(phone, message) if Rails.env.development?

    uri = URI(@api_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = @timeout
    http.open_timeout = @timeout

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    # request['Authorization'] = "Bearer #{@api_key}"

    # 準備請求資料（依據您的簡訊服務商 API 格式調整）
    request.body = {
      to: phone,
      text: message,
      from: @from
      # username: @username,
      # password: @password
    }.to_json

    http.request(request)
  end

  # 檢查響應是否成功
  def response_successful?(response)
    response.code.to_i.between?(200, 299)
  end

  # 測試環境的模擬響應
  def mock_response
    mock_response = Object.new
    mock_response.define_singleton_method(:code) { '200' }
    mock_response.define_singleton_method(:body) { { status: 'sent', id: 'test-123' }.to_json }
    mock_response
  end

  # 開發環境的詳細模擬響應
  def development_mock_response(phone, message)
    # 判斷訊息類型
    message_type = if message.include?('明日用餐提醒')
                     '用餐提醒'
                   elsif message.include?('您已預約')
                     '訂位確認'
                   elsif message.include?('取消')
                     '取消通知'
                   else
                     '一般訊息'
                   end

    Rails.logger.info '🚀 [SmsService] 開發環境模擬簡訊發送'
    Rails.logger.info "🚀 [SmsService] 訊息類型: #{message_type}"
    Rails.logger.info "🚀 [SmsService] 目標電話: #{phone}"
    Rails.logger.info "🚀 [SmsService] 訊息內容: #{message}"
    Rails.logger.info "🚀 [SmsService] 訊息長度: #{message.length} 字"

    # 模擬簡訊計費（每70字為一則）
    sms_count = (message.length / 70.0).ceil
    Rails.logger.info "🚀 [SmsService] 估計簡訊計費: #{sms_count} 則"
    Rails.logger.info '🚀 [SmsService] 模擬發送成功 ✅'

    # 模擬一些處理時間
    sleep(0.1)

    mock_response = Object.new
    mock_response.define_singleton_method(:code) { '200' }
    mock_response.define_singleton_method(:body) do
      {
        status: 'sent',
        id: "dev-#{SecureRandom.hex(6)}",
        to: phone,
        message: message,
        message_type: message_type,
        sms_count: sms_count,
        timestamp: Time.current.iso8601,
        simulation: true
      }.to_json
    end
    mock_response
  end
end
