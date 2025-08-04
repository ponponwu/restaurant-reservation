# 此服務已停用 - 改用樂觀鎖機制
# 保留檔案以便需要時回滾到悲觀鎖機制
# 相關替代方案請參考：
# - Reservation 模型的樂觀鎖 (lock_version)
# - 資料庫唯一約束 (idx_reservations_table_time_conflict)
# - ReservationsController 的樂觀鎖重試機制
class SolidCacheReservationLockService
  LOCK_TIMEOUT = 30.seconds

  class << self
    # 主要鎖定方法 - 使用真正的 Solid Cache
    def with_lock(restaurant_id, datetime, party_size)
      lock_key = generate_lock_key(restaurant_id, datetime, party_size)
      lock_value = generate_lock_value

      begin
        # 使用 unless_exist: true 確保原子性 - 這是 Solid Cache 的標準做法
        # 對於併發預約，我們不重試 - 立即失敗以避免競爭條件
        acquired = Rails.cache.write(lock_key, lock_value,
                                     unless_exist: true,
                                     expires_in: LOCK_TIMEOUT)
      rescue StandardError => e
        Rails.logger.error "Solid Cache 鎖定獲取失敗: #{e.message}"
        raise ConcurrentReservationError, '快取服務不可用，無法獲取鎖定'
      end

      if acquired
        begin
          Rails.logger.info "獲取 Solid Cache 訂位鎖定: #{lock_key}"
          yield
        ensure
          release_lock(lock_key, lock_value)
        end
      else
        Rails.logger.warn "無法獲取 Solid Cache 訂位鎖定: #{lock_key}"
        raise ConcurrentReservationError, '有其他客戶正在預訂相同時段，請稍後再試'
      end
    end

    # 檢查是否有鎖定存在
    def locked?(restaurant_id, datetime, party_size)
      lock_key = generate_lock_key(restaurant_id, datetime, party_size)
      Rails.cache.exist?(lock_key)
    rescue StandardError => e
      Rails.logger.error "檢查 Solid Cache 鎖定狀態失敗: #{e.message}"
      false
    end

    # 強制釋放鎖定（管理用途）
    def force_unlock(restaurant_id, datetime, party_size)
      lock_key = generate_lock_key(restaurant_id, datetime, party_size)
      result = Rails.cache.delete(lock_key)
      Rails.logger.info "強制釋放 Solid Cache 鎖定: #{lock_key}"
      result
    rescue StandardError => e
      Rails.logger.error "強制釋放 Solid Cache 鎖定失敗: #{e.message}"
      false
    end

    # 獲取所有活躍的鎖定 - 簡化版本
    def active_locks
      # Solid Cache 不提供 keys() 方法，所以我們只能返回基本資訊
      # 在實際應用中，這個方法主要用於監控和調試
      Rails.logger.info 'Solid Cache 不支援列舉所有鍵值，回傳空陣列'
      []
    rescue StandardError => e
      Rails.logger.error "獲取活躍 Solid Cache 鎖定失敗: #{e.message}"
      []
    end

    private

    # 生成鎖定鍵值 - 與原版相容
    def generate_lock_key(restaurant_id, datetime, party_size)
      "reservation_lock:#{restaurant_id}:#{datetime.strftime('%Y%m%d_%H%M')}:#{party_size}"
    end

    # 生成唯一的鎖定值
    def generate_lock_value
      "#{Socket.gethostname}:#{Process.pid}:#{Thread.current.object_id}:#{Time.current.to_f}"
    end

    # 釋放鎖定 - 使用 compare-and-delete 邏輯
    def release_lock(lock_key, lock_value)
      # 檢查當前值是否與我們的鎖定值相符
      current_value = Rails.cache.read(lock_key)

      if current_value == lock_value
        # 只有持有鎖定的程序才能釋放
        result = Rails.cache.delete(lock_key)
        Rails.logger.info "釋放 Solid Cache 訂位鎖定: #{lock_key}"
        result
      else
        Rails.logger.warn "無法釋放鎖定 #{lock_key}: 鎖定值不符或已過期"
        false
      end
    rescue StandardError => e
      Rails.logger.error "Solid Cache 鎖定釋放失敗: #{e.message}"
      false
    end
  end
end

# 併發預約錯誤 - 與原版相容
class ConcurrentReservationError < StandardError; end
