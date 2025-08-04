class DailyReminderJob < ApplicationJob
  queue_as :default

  # 重試設定：最多重試 2 次
  retry_on StandardError, wait: :exponentially_longer, attempts: 2

  def perform(date = nil)
    target_date = date&.to_date || Date.current.tomorrow

    Rails.logger.info "DailyReminderJob: Processing daily reminders for #{target_date}"

    # 查找明天需要用餐提醒的訂位
    reservations = find_reservations_for_reminder(target_date)

    if reservations.empty?
      Rails.logger.info "DailyReminderJob: No reservations found for #{target_date}"
      return
    end

    Rails.logger.info "DailyReminderJob: Found #{reservations.count} reservations for #{target_date}"

    # 批次處理簡訊發送
    success_count = 0
    error_count = 0

    reservations.find_each do |reservation|
      # 檢查是否已經發送過用餐提醒
      if already_sent_reminder?(reservation)
        Rails.logger.debug { "DailyReminderJob: Reminder already sent for reservation #{reservation.id}" }
        next
      end

      # 排程簡訊發送作業
      SmsNotificationJob.perform_later(reservation.id, 'dining_reminder')
      success_count += 1

      Rails.logger.debug { "DailyReminderJob: Queued reminder for reservation #{reservation.id}" }
    rescue StandardError => e
      error_count += 1
      Rails.logger.error "DailyReminderJob: Error queuing reminder for reservation #{reservation.id}: #{e.message}"
    end

    Rails.logger.info "DailyReminderJob: Completed processing for #{target_date}. Success: #{success_count}, Errors: #{error_count}"

    # 記錄統計信息（可以後續用於監控）
    log_reminder_statistics(target_date, reservations.count, success_count, error_count)
  rescue StandardError => e
    Rails.logger.error "DailyReminderJob: Fatal error processing daily reminders for #{target_date}: #{e.message}"
    Rails.logger.error "DailyReminderJob: Backtrace: #{e.backtrace.join("\n")}"
    raise
  end

  private

  def find_reservations_for_reminder(target_date)
    # 查找指定日期的已確認訂位
    # 排除已取消、no_show 的訂位
    Reservation.joins(:restaurant)
      .where(reservation_datetime: target_date.all_day)
      .where(status: 'confirmed')
      .where.not(customer_phone: [nil, ''])
      .includes(:restaurant, :sms_logs)
  end

  def already_sent_reminder?(reservation)
    # 檢查是否已經發送過用餐提醒
    # 查看今天是否已經有成功發送的用餐提醒記錄
    reservation.sms_logs
      .where(message_type: 'dining_reminder')
      .where(status: 'sent')
      .where(created_at: Date.current.all_day)
      .exists?
  end

  def log_reminder_statistics(date, total_reservations, success_count, error_count)
    Rails.logger.info "=== Daily Reminder Statistics for #{date} ==="
    Rails.logger.info "Total reservations: #{total_reservations}"
    Rails.logger.info "Successfully queued: #{success_count}"
    Rails.logger.info "Errors: #{error_count}"
    Rails.logger.info "Success rate: #{total_reservations > 0 ? (success_count.to_f / total_reservations * 100).round(2) : 0}%"
    Rails.logger.info '============================================='
  end
end
