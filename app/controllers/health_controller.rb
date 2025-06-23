class HealthController < ApplicationController
  # 跳過 CSRF 保護，因為這是健康檢查端點
  skip_before_action :verify_authenticity_token

  def index
    render json: health_status, status: overall_status
  end

  private

  def health_status
    {
      status: overall_status == 200 ? 'healthy' : 'unhealthy',
      timestamp: Time.current.iso8601,
      environment: Rails.env,
      version: app_version,
      checks: {
        database: database_check,
        redis: redis_check
      }
    }
  end

  def overall_status
    checks = [
      database_check[:status],
      redis_check[:status]
    ]

    checks.all?('ok') ? 200 : 503
  end

  def database_check
    start_time = Time.current
    ActiveRecord::Base.connection.execute('SELECT 1')
    response_time = ((Time.current - start_time) * 1000).round(2)

    {
      status: 'ok',
      response_time_ms: response_time
    }
  rescue StandardError => e
    {
      status: 'error',
      error: e.message
    }
  end

  def redis_check
    return { status: 'unavailable', error: 'Redis not configured' } unless defined?(Redis.current)

    start_time = Time.current
    Redis.current.ping
    response_time = ((Time.current - start_time) * 1000).round(2)

    {
      status: 'ok',
      response_time_ms: response_time
    }
  rescue StandardError => e
    {
      status: 'error',
      error: e.message
    }
  end

  def app_version
    # 嘗試從 Git 獲取版本資訊
    return ENV['APP_VERSION'] if ENV['APP_VERSION'].present?

    if File.exist?('.git/HEAD')
      head_content = File.read('.git/HEAD').strip
      if head_content.start_with?('ref: ')
        ref_file = head_content[5..]
        File.read(".git/#{ref_file}").strip[0..7] if File.exist?(".git/#{ref_file}")
      else
        head_content[0..7]
      end
    else
      'unknown'
    end
  rescue StandardError
    'unknown'
  end
end
