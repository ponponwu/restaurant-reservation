class SmsNotificationJob < ApplicationJob
  queue_as :default

  # 重試設定：最多重試 3 次，每次間隔遞增
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(reservation_id, message_type, options = {})
    reservation = Reservation.find(reservation_id)

    Rails.logger.info "SmsNotificationJob: Processing #{message_type} for reservation #{reservation_id}"

    # 檢查訂位是否仍然有效
    unless reservation_valid_for_notification?(reservation, message_type)
      Rails.logger.warn "SmsNotificationJob: Reservation #{reservation_id} not valid for #{message_type}"
      return
    end

    # 初始化簡訊服務
    sms_service = SmsService.new

    # 根據訊息類型發送對應的簡訊
    case message_type.to_s
    when 'reservation_confirmation'
      send_confirmation_sms(sms_service, reservation)
    when 'dining_reminder'
      send_reminder_sms(sms_service, reservation)
    when 'reservation_cancellation'
      cancellation_reason = options[:cancellation_reason]
      send_cancellation_sms(sms_service, reservation, cancellation_reason)
    else
      Rails.logger.error "SmsNotificationJob: Unknown message type: #{message_type}"
      raise ArgumentError, "Unknown message type: #{message_type}"
    end

    Rails.logger.info "SmsNotificationJob: Successfully processed #{message_type} for reservation #{reservation_id}"
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "SmsNotificationJob: Reservation #{reservation_id} not found: #{e.message}"
    # 不重試，因為記錄不存在
  rescue StandardError => e
    Rails.logger.error "SmsNotificationJob: Error processing #{message_type} for reservation #{reservation_id}: #{e.message}"
    Rails.logger.error "SmsNotificationJob: Backtrace: #{e.backtrace.join("\n")}"
    raise # 重新拋出異常以觸發重試機制
  end

  private

  def reservation_valid_for_notification?(reservation, message_type)
    case message_type.to_s
    when 'reservation_confirmation'
      # 確認通知：訂位必須是已確認狀態
      reservation.confirmed?
    when 'dining_reminder'
      # 用餐提醒：訂位必須是已確認狀態且還沒到用餐時間
      reservation.confirmed? && !reservation.is_past?
    when 'reservation_cancellation'
      # 取消通知：訂位必須是已取消狀態
      reservation.cancelled?
    else
      false
    end
  end

  def send_confirmation_sms(sms_service, reservation)
    result = sms_service.send_reservation_confirmation(reservation)

    return if result[:success]

    Rails.logger.error "SmsNotificationJob: Failed to send confirmation SMS: #{result[:error]}"
    raise StandardError, "Failed to send confirmation SMS: #{result[:error]}"
  end

  def send_reminder_sms(sms_service, reservation)
    result = sms_service.send_dining_reminder(reservation)

    return if result[:success]

    Rails.logger.error "SmsNotificationJob: Failed to send reminder SMS: #{result[:error]}"
    raise StandardError, "Failed to send reminder SMS: #{result[:error]}"
  end

  def send_cancellation_sms(sms_service, reservation, cancellation_reason = nil)
    result = sms_service.send_reservation_cancellation(reservation, cancellation_reason)

    return if result[:success]

    Rails.logger.error "SmsNotificationJob: Failed to send cancellation SMS: #{result[:error]}"
    raise StandardError, "Failed to send cancellation SMS: #{result[:error]}"
  end
end
