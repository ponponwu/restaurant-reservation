# 舊版本的 ReservationLockService (備份)
# 此檔案僅作為備份用途，請使用 EnhancedReservationLockService

class ReservationLockServiceLegacy
  LOCK_TIMEOUT = 30.seconds

  def self.with_lock(restaurant_id, datetime, party_size)
    lock_key = "reservation_lock:#{restaurant_id}:#{datetime.strftime('%Y%m%d_%H%M')}:#{party_size}"
    lock_value = "#{Process.pid}:#{Thread.current.object_id}:#{Time.current.to_f}"

    # 嘗試獲取鎖定，使用 SET NX EX 原子操作
    acquired = Rails.cache.write(lock_key, lock_value, expires_in: LOCK_TIMEOUT, unless_exist: true)

    unless acquired
      # 檢查現有鎖定是否過期
      existing_lock = Rails.cache.read(lock_key)
      if existing_lock.nil?
        # 鎖定已過期，重試獲取
        acquired = Rails.cache.write(lock_key, lock_value, expires_in: LOCK_TIMEOUT, unless_exist: true)
      end
    end

    if acquired
      begin
        Rails.logger.info "獲取訂位鎖定: #{lock_key} by #{lock_value}"
        yield
      ensure
        # 只有持有鎖定的程序才能釋放鎖定
        current_lock = Rails.cache.read(lock_key)
        if current_lock == lock_value
          Rails.cache.delete(lock_key)
          Rails.logger.info "釋放訂位鎖定: #{lock_key} by #{lock_value}"
        end
      end
    else
      # 無法獲取鎖定，表示有其他人正在處理相同的訂位
      Rails.logger.warn "無法獲取訂位鎖定: #{lock_key}, 現有鎖定: #{Rails.cache.read(lock_key)}"
      raise ConcurrentReservationError, '有其他客戶正在預訂相同時段，請稍後再試'
    end
  end
end
