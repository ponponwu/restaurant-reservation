# 訂位鎖定管理器 - 統一介面，支援 Redis 和 PostgreSQL 實現
class ReservationLockManager
  class << self
    # 主要鎖定方法 - 根據配置選擇實現
    def with_lock(restaurant_id, datetime, party_size, &block)
      lock_service.with_lock(restaurant_id, datetime, party_size, &block)
    end

    # 檢查是否有鎖定存在
    def locked?(restaurant_id, datetime, party_size)
      lock_service.locked?(restaurant_id, datetime, party_size)
    end

    # 強制釋放鎖定（管理用途）
    def force_unlock(restaurant_id, datetime, party_size)
      lock_service.force_unlock(restaurant_id, datetime, party_size)
    end

    # 獲取所有活躍的鎖定
    def active_locks
      lock_service.active_locks
    end

    # 獲取當前使用的鎖定服務
    def current_service
      use_postgres_locks? ? :postgres : :redis
    end

    private

    # 根據配置選擇鎖定服務
    def lock_service
      if use_postgres_locks?
        PostgresReservationLockService
      else
        EnhancedReservationLockService
      end
    end

    # 檢查是否使用 PostgreSQL 鎖定
    def use_postgres_locks?
      # 優先檢查環境變數
      return ENV['USE_POSTGRES_LOCKS'] == 'true' if ENV.key?('USE_POSTGRES_LOCKS')
      
      # 檢查 Rails 配置
      return Rails.application.config.use_postgres_locks if Rails.application.config.respond_to?(:use_postgres_locks)
      
      # 根據環境決定預設值
      case Rails.env
      when 'development'
        # 開發環境可以切換測試
        Rails.cache.read('use_postgres_locks') || false
      when 'test'
        # 測試環境預設使用 PostgreSQL（更快，無需外部依賴）
        true
      when 'production'
        # 生產環境預設仍使用 Redis（保守策略）
        false
      else
        false
      end
    end
  end

  # 執行期間切換鎖定實現（開發/測試用）
  class << self
    def switch_to_postgres!
      Rails.cache.write('use_postgres_locks', true)
      Rails.logger.info '切換到 PostgreSQL Advisory Locks'
    end

    def switch_to_redis!
      Rails.cache.write('use_postgres_locks', false)
      Rails.logger.info '切換到 Redis Locks'
    end

    def status_info
      {
        current_service: current_service,
        postgres_available: postgres_available?,
        redis_available: redis_available?,
        environment: Rails.env,
        config_source: lock_config_source
      }
    end

    private

    def postgres_available?
      ApplicationRecord.connection.execute('SELECT 1').any?
    rescue StandardError
      false
    end

    def redis_available?
      defined?(Redis.current) && Redis.current&.ping == 'PONG'
    rescue StandardError
      false
    end

    def lock_config_source
      return 'ENV[USE_POSTGRES_LOCKS]' if ENV.key?('USE_POSTGRES_LOCKS')
      return 'Rails.config.use_postgres_locks' if Rails.application.config.respond_to?(:use_postgres_locks)
      return 'Rails.cache' if Rails.env.development?
      return 'default_test' if Rails.env.test?
      return 'default_production' if Rails.env.production?
      
      'default_other'
    end
  end
end