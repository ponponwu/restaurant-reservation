# ReservationLockService 使用 SolidCacheReservationLockService 作為後端
# 提供統一的介面給應用程式使用

class ReservationLockService
  class << self
    # 主要鎖定方法 - 委派給 SolidCacheReservationLockService
    def with_lock(restaurant_id, datetime, party_size, &block)
      SolidCacheReservationLockService.with_lock(restaurant_id, datetime, party_size, &block)
    end

    # 檢查鎖定狀態
    def locked?(restaurant_id, datetime, party_size)
      SolidCacheReservationLockService.locked?(restaurant_id, datetime, party_size)
    end

    # 強制解鎖
    def force_unlock(restaurant_id, datetime, party_size)
      SolidCacheReservationLockService.force_unlock(restaurant_id, datetime, party_size)
    end

    # 取得活躍的鎖定
    def active_locks
      SolidCacheReservationLockService.active_locks
    end

    # 服務資訊
    def service_info
      {
        version: '3.0 (Solid Cache)',
        backend: 'Solid Cache',
        service: 'SolidCacheReservationLockService'
      }
    end
  end
end

# 確保例外類別可用
class ConcurrentReservationError < StandardError; end
class RedisConnectionError < StandardError; end
