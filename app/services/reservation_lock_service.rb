# ReservationLockService 現在是 EnhancedReservationLockService 的別名
# 這確保了向後相容性，現有代碼無需修改

# 載入新的增強服務
require_dependency Rails.root.join('app', 'services', 'enhanced_reservation_lock_service')

class ReservationLockService
  class << self
    # 將所有方法委派給 EnhancedReservationLockService
    def with_lock(restaurant_id, datetime, party_size, &block)
      EnhancedReservationLockService.with_lock(restaurant_id, datetime, party_size, &block)
    end

    delegate :locked?, to: :EnhancedReservationLockService

    delegate :force_unlock, to: :EnhancedReservationLockService

    delegate :active_locks, to: :EnhancedReservationLockService

    # 提供遷移信息的方法
    def migration_info
      {
        version: '2.0 (Enhanced Redis)',
        backend: 'Redis',
        legacy_file: 'reservation_lock_service_legacy.rb',
        new_service: 'EnhancedReservationLockService',
        upgrade_date: Time.current.to_s
      }
    end

    # 檢查是否已升級
    def upgraded?
      true
    end

    # 記錄升級訊息
    def log_upgrade_info
      info = migration_info
      Rails.logger.info 'ReservationLockService 已升級：'
      Rails.logger.info "  版本: #{info[:version]}"
      Rails.logger.info "  後端: #{info[:backend]}"
      Rails.logger.info "  新服務: #{info[:new_service]}"
      Rails.logger.info "  升級時間: #{info[:upgrade_date]}"
    end
  end
end

# 確保例外類別仍然可用
class ConcurrentReservationError < StandardError; end
class RedisConnectionError < StandardError; end

# 記錄升級訊息（僅在第一次載入時）
unless defined?(@@upgrade_logged)
  @@upgrade_logged = true
  Rails.logger.info 'ReservationLockService 已成功升級為使用 Redis 後端'
end
