namespace :sms do
  desc 'Send daily dining reminders at 12:00 PM'
  task send_daily_reminders: :environment do
    puts "Starting daily SMS reminders task at #{Time.current}"

    # 檢查簡訊服務是否啟用
    unless Rails.env.production? || ENV['SMS_SERVICE_ENABLED'] == 'true'
      puts 'SMS service is disabled. Skipping daily reminders.'
      exit
    end

    begin
      # 執行明天的用餐提醒
      target_date = Date.current.tomorrow
      puts "Processing daily reminders for #{target_date}"

      # 排程 DailyReminderJob 執行
      DailyReminderJob.perform_later(target_date)

      puts "Daily reminder job has been queued for #{target_date}"
    rescue StandardError => e
      puts "Error in daily reminders task: #{e.message}"
      puts "Backtrace: #{e.backtrace.join("\n")}"
      raise
    end
  end

  desc 'Send daily dining reminders for a specific date'
  task :send_reminders_for_date, [:date] => :environment do |_task, args|
    date = args[:date] ? Date.parse(args[:date]) : Date.current.tomorrow

    puts "Starting SMS reminders for #{date}"

    # 檢查簡訊服務是否啟用
    unless Rails.env.production? || ENV['SMS_SERVICE_ENABLED'] == 'true'
      puts "SMS service is disabled. Skipping reminders for #{date}."
      exit
    end

    begin
      # 排程 DailyReminderJob 執行
      DailyReminderJob.perform_later(date)

      puts "Reminder job has been queued for #{date}"
    rescue StandardError => e
      puts "Error in reminders task for #{date}: #{e.message}"
      puts "Backtrace: #{e.backtrace.join("\n")}"
      raise
    end
  end

  desc 'Test SMS service configuration'
  task test_sms_service: :environment do
    puts 'Testing SMS service configuration...'

    # 檢查環境變數
    required_vars = %w[SMS_SERVICE_URL SMS_SERVICE_API_KEY SMS_SERVICE_FROM]
    missing_vars = required_vars.select { |var| ENV[var].blank? }

    if missing_vars.any?
      puts "Missing required environment variables: #{missing_vars.join(', ')}"
      exit 1
    end

    puts 'Environment variables configured:'
    puts "  SMS_SERVICE_URL: #{ENV.fetch('SMS_SERVICE_URL', nil)}"
    puts "  SMS_SERVICE_API_KEY: #{ENV['SMS_SERVICE_API_KEY'].present? ? '[CONFIGURED]' : '[MISSING]'}"
    puts "  SMS_SERVICE_FROM: #{ENV.fetch('SMS_SERVICE_FROM', nil)}"
    puts "  SMS_SERVICE_ENABLED: #{ENV.fetch('SMS_SERVICE_ENABLED', nil)}"
    puts "  SMS_SERVICE_TIMEOUT: #{ENV.fetch('SMS_SERVICE_TIMEOUT', nil)}"

    # 測試服務連線（不實際發送簡訊）
    begin
      SmsService.new
      puts 'SMS service initialized successfully'

      # 可以在這裡加入更多測試邏輯
      puts 'SMS service test completed successfully'
    rescue StandardError => e
      puts "SMS service test failed: #{e.message}"
      exit 1
    end
  end

  desc 'Show SMS statistics'
  task show_stats: :environment do
    puts 'SMS Statistics:'
    puts '=' * 50

    # 總體統計
    total_logs = SmsLog.count
    sent_logs = SmsLog.sent.count
    failed_logs = SmsLog.failed.count

    puts "Total SMS logs: #{total_logs}"
    puts "Successfully sent: #{sent_logs}"
    puts "Failed: #{failed_logs}"
    puts "Success rate: #{total_logs > 0 ? (sent_logs.to_f / total_logs * 100).round(2) : 0}%"

    # 今日統計
    today_logs = SmsLog.for_date(Date.current)
    today_sent = today_logs.sent.count
    today_failed = today_logs.failed.count

    puts "\nToday's statistics:"
    puts "Total sent today: #{today_sent}"
    puts "Failed today: #{today_failed}"

    # 依訊息類型統計
    puts "\nBy message type:"
    SmsLog.distinct.pluck(:message_type).each do |type|
      count = SmsLog.where(message_type: type).count
      sent_count = SmsLog.where(message_type: type, status: 'sent').count
      puts "  #{type}: #{count} total, #{sent_count} sent"
    end

    # 最近失敗的簡訊
    recent_failures = SmsLog.failed.recent.limit(5)
    if recent_failures.any?
      puts "\nRecent failures:"
      recent_failures.each do |log|
        puts "  #{log.formatted_created_at} - #{log.message_type} to #{log.phone_number}"
      end
    end
  end
end
