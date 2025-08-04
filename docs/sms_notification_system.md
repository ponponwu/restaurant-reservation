# SMS Notification System

## Overview

This document describes the SMS notification system implemented for the restaurant reservation system. The system provides automated SMS notifications for reservation confirmations, daily reminders, and cancellation notifications.

## Architecture

### Components

1. **SmsService** - Core service for sending SMS messages
2. **SmsNotificationJob** - Background job for asynchronous SMS sending
3. **DailyReminderJob** - Batch job for daily reminder processing
4. **SmsLog** - Model for tracking SMS sending history

### Technology Stack

- **Rails 8** with Solid Queue for background job processing
- **PostgreSQL** for data storage and job queue
- **Custom SMS Service** integration via HTTP API
- **Comprehensive logging** and error handling

## Features

### 1. Reservation Confirmation SMS

Automatically sent when a reservation status changes to "confirmed":

```
🍽️ 美食餐廳 訂位確認
━━━━━━━━━━━━━━━━━━━━
👤 訂位人：張三
📅 用餐時間：2024/01/15 18:00
👥 用餐人數：2人
🪑 桌位：1號桌
━━━━━━━━━━━━━━━━━━━━
📞 如需異動或取消，請撥打：02-12345678
💻 或點擊線上取消：https://...

期待您的光臨！🌟
```

### 2. Daily Dining Reminders

Sent at 12:00 PM daily for next day's reservations:

```
⏰ 美食餐廳 用餐提醒
━━━━━━━━━━━━━━━━━━━━
👤 張三 您好，
提醒您明天的用餐時間：

📅 日期：2024/01/15
⏰ 時間：18:00
👥 人數：2人
🪑 桌位：1號桌
━━━━━━━━━━━━━━━━━━━━
📍 地址：台北市信義區...
📞 電話：02-12345678

期待您的光臨！🌟
```

### 3. Cancellation Notifications

Sent when a reservation is cancelled:

```
❌ 美食餐廳 訂位取消
━━━━━━━━━━━━━━━━━━━━
👤 張三 您好，
您的訂位已取消：

📅 日期：2024/01/15
⏰ 時間：18:00
👥 人數：2人
📝 取消原因：臨時有事
━━━━━━━━━━━━━━━━━━━━
如有任何問題，請聯繫餐廳：
📞 電話：02-12345678

感謝您的使用！
```

## Configuration

### Environment Variables

```bash
# SMS Service Configuration
SMS_SERVICE_URL=https://your-sms-service.com/api/send
SMS_SERVICE_API_KEY=your-api-key-here
SMS_SERVICE_USERNAME=your-username
SMS_SERVICE_PASSWORD=your-password
SMS_SERVICE_FROM=your-restaurant-name
SMS_SERVICE_ENABLED=true
SMS_SERVICE_TIMEOUT=30
```

### Solid Queue Configuration

The system uses Rails 8 Solid Queue for background job processing:

```yaml
# config/queue.yml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"
      threads: 5
      processes: 2
      polling_interval: 0.1
```

## Usage

### Manual SMS Sending

```ruby
# Send confirmation SMS
sms_service = SmsService.new
result = sms_service.send_reservation_confirmation(reservation)

# Send reminder SMS
result = sms_service.send_dining_reminder(reservation)

# Send cancellation SMS
result = sms_service.send_reservation_cancellation(reservation, reason)
```

### Background Job Processing

```ruby
# Queue confirmation SMS
SmsNotificationJob.perform_later(reservation.id, 'reservation_confirmation')

# Queue reminder SMS
SmsNotificationJob.perform_later(reservation.id, 'dining_reminder')

# Queue cancellation SMS
SmsNotificationJob.perform_later(reservation.id, 'reservation_cancellation', 
  { cancellation_reason: 'Customer requested' })
```

### Daily Reminder Processing

```ruby
# Process daily reminders for tomorrow
DailyReminderJob.perform_later(Date.current.tomorrow)

# Process for specific date
DailyReminderJob.perform_later(Date.parse('2024-01-15'))
```

## Rake Tasks

### Daily Reminder Tasks

```bash
# Send daily reminders for tomorrow
rake sms:send_daily_reminders

# Send reminders for specific date
rake sms:send_reminders_for_date[2024-01-15]
```

### Monitoring Tasks

```bash
# Test SMS service configuration
rake sms:test_sms_service

# Show SMS statistics
rake sms:show_stats
```

## Cron Job Setup

Add to your crontab for daily execution:

```bash
# Send daily SMS reminders at 12:00 PM
0 12 * * * cd /path/to/restaurant-reservation && RAILS_ENV=production bundle exec rake sms:send_daily_reminders
```

## Error Handling

### Automatic Retry

- SMS jobs are automatically retried up to 3 times
- Uses exponential backoff for retry delays
- Failed jobs are logged with detailed error information

### Error Logging

```ruby
# Check recent failures
rake sms:show_stats

# View SMS logs
SmsLog.failed.recent.each do |log|
  puts "#{log.formatted_created_at} - #{log.message_type} to #{log.phone_number}: #{log.response_data}"
end
```

## Monitoring

### Database Monitoring

```sql
-- Check SMS sending statistics
SELECT 
  message_type,
  status,
  COUNT(*) as count,
  COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() as percentage
FROM sms_logs 
WHERE created_at >= NOW() - INTERVAL '1 day'
GROUP BY message_type, status
ORDER BY message_type, status;
```

### Application Monitoring

```ruby
# Success rate monitoring
def sms_success_rate(date = Date.current)
  logs = SmsLog.for_date(date)
  return 0 if logs.empty?
  
  (logs.successful.count.to_f / logs.count * 100).round(2)
end

# Daily statistics
def daily_sms_stats
  {
    total_sent: SmsLog.for_date(Date.current).sent.count,
    total_failed: SmsLog.for_date(Date.current).failed.count,
    success_rate: sms_success_rate
  }
end
```

## Security Considerations

1. **API Key Protection**: Store SMS service credentials securely
2. **Rate Limiting**: Implement rate limiting to prevent abuse
3. **Input Validation**: Validate phone numbers and message content
4. **Audit Logging**: All SMS activities are logged in SmsLog model
5. **Encryption**: Use HTTPS for all SMS service communications

## Performance Optimization

1. **Background Processing**: All SMS sending is asynchronous
2. **Batch Processing**: Daily reminders are processed in batches
3. **Database Indexing**: Optimized queries for SMS log retrieval
4. **Caching**: Environment variables are cached for performance
5. **Connection Pooling**: HTTP connections are reused when possible

## Testing

### Unit Tests

```bash
# Run SMS service tests
bundle exec rspec spec/services/sms_service_spec.rb

# Run job tests
bundle exec rspec spec/jobs/sms_notification_job_spec.rb
bundle exec rspec spec/jobs/daily_reminder_job_spec.rb
```

### Integration Tests

```bash
# Run integration tests
bundle exec rspec spec/integration/sms_notification_integration_spec.rb
```

### Manual Testing

```ruby
# Test SMS service in Rails console
sms_service = SmsService.new
reservation = Reservation.confirmed.first
result = sms_service.send_reservation_confirmation(reservation)
puts result.inspect
```

## Troubleshooting

### Common Issues

1. **SMS not sending**: Check environment variables and service configuration
2. **Job not processing**: Ensure Solid Queue worker is running
3. **High failure rate**: Review SMS service logs and API documentation
4. **Missing reminders**: Check cron job configuration and execution

### Debug Commands

```bash
# Check environment configuration
rake sms:test_sms_service

# View recent failures
rake sms:show_stats

# Test specific reservation
rails console
reservation = Reservation.find(123)
SmsNotificationJob.perform_now(reservation.id, 'reservation_confirmation')
```

## Future Enhancements

1. **Template Management**: Web interface for SMS template customization
2. **Multi-language Support**: Localized SMS messages
3. **SMS Analytics**: Detailed reporting and analytics dashboard
4. **Integration Options**: Support for multiple SMS service providers
5. **Customer Preferences**: Allow customers to opt-out of SMS notifications

## Support

For technical support or questions about the SMS notification system, please refer to:

- System logs: `log/production.log`
- Error monitoring: SMS statistics and failure logs
- Documentation: This file and inline code comments
- Test suite: Comprehensive test coverage for all components