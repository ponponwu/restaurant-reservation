require 'zlib'

class PostgresReservationLockService
  LOCK_TIMEOUT = 30.seconds
  RETRY_ATTEMPTS = 3
  RETRY_DELAY = 0.1.seconds

  class << self
    # 主要鎖定方法 - API 相容於 EnhancedReservationLockService
    def with_lock(restaurant_id, datetime, party_size)
      lock_key = generate_lock_key(restaurant_id, datetime, party_size)

      attempts = 0

      while attempts < RETRY_ATTEMPTS
        # 使用 timeout_seconds: 0 讓它立即返回而不等待
        result = ApplicationRecord.with_advisory_lock_result(lock_key, timeout_seconds: 0) do
          Rails.logger.info "獲取 PostgreSQL 訂位鎖定: #{lock_key}"
          yield
        end

        if result.lock_was_acquired?
          return result.result
        else
          attempts += 1
          Rails.logger.debug "PostgreSQL 鎖定獲取失敗，嘗試 #{attempts}/#{RETRY_ATTEMPTS}: #{lock_key}"
          
          if attempts < RETRY_ATTEMPTS
            sleep(RETRY_DELAY + rand(0.05))
          end
        end
      end

      Rails.logger.warn "無法獲取 PostgreSQL 訂位鎖定: #{lock_key} (嘗試 #{attempts} 次)"
      raise ConcurrentReservationError, '有其他客戶正在預訂相同時段，請稍後再試'
    end

    # 檢查是否有鎖定存在 - 使用 advisory_lock_exists? 方法
    def locked?(restaurant_id, datetime, party_size)
      lock_key = generate_lock_key(restaurant_id, datetime, party_size)
      
      ApplicationRecord.advisory_lock_exists?(lock_key)
    rescue StandardError => e
      Rails.logger.error "檢查 PostgreSQL 鎖定狀態失敗: #{e.message}"
      false
    end

    # 強制釋放鎖定（管理用途）- PostgreSQL advisory locks 會在連接結束時自動釋放
    def force_unlock(restaurant_id, datetime, party_size)
      lock_key = generate_lock_key(restaurant_id, datetime, party_size)
      
      # PostgreSQL advisory locks 是 session-based，無法從外部強制釋放
      # 只能檢查鎖定是否存在
      was_locked = locked?(restaurant_id, datetime, party_size)
      
      if was_locked
        Rails.logger.warn "PostgreSQL 鎖定 #{lock_key} 仍然存在，需等待持有者釋放或 session 結束"
        false
      else
        Rails.logger.info "PostgreSQL 鎖定 #{lock_key} 不存在或已釋放"
        true
      end
    rescue StandardError => e
      Rails.logger.error "檢查 PostgreSQL 鎖定狀態失敗: #{e.message}"
      false
    end

    # 獲取所有活躍的鎖定 - 簡化版本
    def active_locks
      # 由於 with_advisory_lock gem 使用字符串 hash，我們無法輕易反向查找所有鎖定
      # 這個方法主要用於監控，可以返回一個基本的實現
      result = ApplicationRecord.connection.execute(<<~SQL)
        SELECT 
          objid as lock_id,
          objsubid,
          pid,
          granted
        FROM pg_locks 
        WHERE locktype = 'advisory' 
          AND granted = true
      SQL

      result.map do |row|
        {
          key: "advisory_lock_#{row['lock_id']}_#{row['objsubid']}",
          lock_id: row['lock_id'].to_i,
          objsubid: row['objsubid'].to_i,
          pid: row['pid'].to_i,
          granted: row['granted'] == 't'
        }
      end.select { |lock| lock[:key].include?('reservation') if lock[:key].is_a?(String) }
    rescue StandardError => e
      Rails.logger.error "獲取活躍 PostgreSQL 鎖定失敗: #{e.message}"
      []
    end

    private

    # 生成鎖定鍵值 - 與 Redis 版本相容
    def generate_lock_key(restaurant_id, datetime, party_size)
      "reservation_lock:#{restaurant_id}:#{datetime.strftime('%Y%m%d_%H%M')}:#{party_size}"
    end
  end
end

# 併發預約錯誤 - 與原版相容
class ConcurrentReservationError < StandardError; end