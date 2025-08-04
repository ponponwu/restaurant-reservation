# Cron Jobs Configuration

This document describes the cron jobs needed for the SMS notification system.

## Daily Reminder Job

The daily reminder job should be scheduled to run every day at 12:00 PM to send dining reminders to customers who have reservations for the next day.

### Manual Cron Setup

Add this line to your crontab (`crontab -e`):

```bash
# Send daily SMS reminders at 12:00 PM
0 12 * * * cd /path/to/restaurant-reservation && RAILS_ENV=production bundle exec rake sms:send_daily_reminders
```

### Using Whenever Gem (Recommended)

If you're using the `whenever` gem for Rails cron jobs, add this to your `config/schedule.rb`:

```ruby
# config/schedule.rb
every 1.day, at: '12:00 PM' do
  rake "sms:send_daily_reminders"
end
```

Then run:
```bash
whenever --update-crontab
```

## Environment Variables

Make sure these environment variables are properly set in your production environment:

```bash
SMS_SERVICE_URL=https://your-sms-service.com/api/send
SMS_SERVICE_API_KEY=your-api-key-here
SMS_SERVICE_USERNAME=your-username
SMS_SERVICE_PASSWORD=your-password
SMS_SERVICE_FROM=your-restaurant-name
SMS_SERVICE_ENABLED=true
SMS_SERVICE_TIMEOUT=30
```

## Available Rake Tasks

```bash
# Send daily reminders for tomorrow
rake sms:send_daily_reminders

# Send reminders for a specific date
rake sms:send_reminders_for_date[2024-01-15]

# Test SMS service configuration
rake sms:test_sms_service

# Show SMS statistics
rake sms:show_stats
```

## Monitoring

You can monitor the SMS service using:

1. **Rails logs** - Check `log/production.log` for SMS-related messages
2. **SMS statistics** - Run `rake sms:show_stats` to see success rates
3. **Database logs** - Query the `sms_logs` table for detailed information

## Solid Queue Management

To manage the background job queue:

```bash
# Start Solid Queue worker
bundle exec rake solid_queue:start

# Stop Solid Queue worker
bundle exec rake solid_queue:stop

# Check job status
bundle exec rake solid_queue:jobs

# Clear failed jobs
bundle exec rake solid_queue:clear_failed

# Clear all jobs
bundle exec rake solid_queue:clear_all
```

## Troubleshooting

### Common Issues

1. **SMS service not responding**: Check network connectivity and API credentials
2. **Jobs not processing**: Ensure Solid Queue worker is running
3. **No reminders sent**: Check if `SMS_SERVICE_ENABLED=true` is set
4. **High failure rate**: Review SMS service logs and API documentation

### Debug Commands

```bash
# Test SMS service
rake sms:test_sms_service

# Check recent failures
rake sms:show_stats

# Manual reminder test
rake sms:send_reminders_for_date[tomorrow]
```