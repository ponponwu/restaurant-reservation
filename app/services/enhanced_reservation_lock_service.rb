class EnhancedReservationLockService
  LOCK_TIMEOUT = 30.seconds
  RETRY_ATTEMPTS = 3
  RETRY_DELAY = 0.1.seconds

  class << self
    # 主要鎖定方法
    def with_lock(restaurant_id, datetime, party_size)
      lock_key = generate_lock_key(restaurant_id, datetime, party_size)
      lock_value = generate_lock_value

      acquired = false
      attempts = 0

      while attempts < RETRY_ATTEMPTS && !acquired
        acquired = acquire_lock(lock_key, lock_value)
        attempts += 1

        sleep(RETRY_DELAY + rand(0.05)) if !acquired && (attempts < RETRY_ATTEMPTS)
      end

      if acquired
        begin
          Rails.logger.info "獲取訂位鎖定: #{lock_key} by #{lock_value}"
          yield
        ensure
          release_lock(lock_key, lock_value)
        end
      else
        Rails.logger.warn "無法獲取訂位鎖定: #{lock_key} (嘗試 #{attempts} 次)"
        raise ConcurrentReservationError, '有其他客戶正在預訂相同時段，請稍後再試'
      end
    end

    # 檢查是否有鎖定存在
    def locked?(restaurant_id, datetime, party_size)
      lock_key = generate_lock_key(restaurant_id, datetime, party_size)
      redis.exists?(lock_key).positive?
    end

    # 強制釋放鎖定（管理用途）
    def force_unlock(restaurant_id, datetime, party_size)
      lock_key = generate_lock_key(restaurant_id, datetime, party_size)
      result = redis.del(lock_key)
      Rails.logger.info "強制釋放鎖定: #{lock_key}, 結果: #{result}"
      result.positive?
    end

    # 獲取所有活躍的鎖定
    def active_locks
      pattern = 'reservation_lock:*'
      keys = redis.keys(pattern)

      locks = keys.map do |key|
        ttl = redis.ttl(key)
        value = redis.get(key)

        {
          key: key,
          value: value,
          ttl: ttl,
          expires_at: ttl.positive? ? Time.current + ttl.seconds : nil
        }
      end

      locks.select { |lock| lock[:ttl].positive? }
    end

    private

    # 生成鎖定鍵值
    def generate_lock_key(restaurant_id, datetime, party_size)
      "reservation_lock:#{restaurant_id}:#{datetime.strftime('%Y%m%d_%H%M')}:#{party_size}"
    end

    # 生成唯一的鎖定值
    def generate_lock_value
      "#{Socket.gethostname}:#{Process.pid}:#{Thread.current.object_id}:#{Time.current.to_f}"
    end

    # 獲取鎖定（使用 Redis 原子操作）
    def acquire_lock(lock_key, lock_value)
      # 使用 SET key value NX EX timeout 原子操作
      result = redis.set(lock_key, lock_value, nx: true, ex: LOCK_TIMEOUT)
      result == 'OK'
    rescue Redis::BaseError => e
      Rails.logger.error "Redis 鎖定獲取失敗: #{e.message}"
      false
    end

    # 釋放鎖定（使用 Lua 腳本確保原子性）
    def release_lock(lock_key, lock_value)
      # Lua 腳本確保只有持有鎖定的程序才能釋放
      lua_script = <<~LUA
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("del", KEYS[1])
        else
          return 0
        end
      LUA

      result = redis.eval(lua_script, keys: [lock_key], argv: [lock_value])

      if result == 1
        Rails.logger.info "釋放訂位鎖定: #{lock_key} by #{lock_value}"
      else
        Rails.logger.warn "無法釋放鎖定 #{lock_key}: 可能已過期或被其他程序持有"
      end

      result == 1
    rescue Redis::BaseError => e
      Rails.logger.error "Redis 鎖定釋放失敗: #{e.message}"
      false
    end

    # Redis 連接
    def redis
      # 在測試環境中，優先使用記憶體快取
      @redis ||= if Rails.env.test?
                   # 使用簡單的記憶體實現
                   @test_redis ||= TestRedis.new
                 elsif defined?(Redis) && Redis.current
                   Redis.current
                 elsif defined?(Sidekiq)
                   # 如果有 Sidekiq，使用其 Redis 配置
                   Sidekiq.redis_pool.with { |conn| conn }
                 else
                   # 建立新的 Redis 連接
                   Redis.new(
                     url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
                     timeout: 1,
                     reconnect_attempts: 3
                   )
                 end
    rescue StandardError => e
      Rails.logger.error "Redis 連接失敗: #{e.message}"
      # 在測試環境中使用替代實現
      raise RedisConnectionError, '無法連接到 Redis 服務器' unless Rails.env.test?

      @test_redis ||= TestRedis.new
    end
  end
end

# 測試環境中的 Redis 模擬實現
class TestRedis
  def initialize
    @data = {}
    @expires = {}
  end

  def set(key, value, options = {})
    if options[:nx] && @data.key?(key) && !expired?(key)
      # NX 選項：只有鍵不存在時才設定
      return nil
    end

    @data[key] = value
    @expires[key] = Time.current + options[:ex].seconds if options[:ex]
    'OK'
  end

  def get(key)
    return nil if expired?(key)

    @data[key]
  end

  def del(key)
    @expires.delete(key)
    @data.delete(key) ? 1 : 0
  end

  def exists?(key)
    return 0 if expired?(key)

    @data.key?(key) ? 1 : 0
  end

  def keys(pattern)
    regex = pattern.gsub('*', '.*')
    @data.keys.select { |k| k.match(/#{regex}/) && !expired?(k) }
  end

  def ttl(key)
    return -1 unless @expires[key]
    return -2 if expired?(key)

    (@expires[key] - Time.current).to_i
  end

  def eval(script, keys:, argv:)
    # 簡單的 Lua 腳本模擬
    key = keys.first
    value = argv.first
    if script.include?('redis.call("get", KEYS[1]) == ARGV[1]')
      @data[key] == value ? del(key) : 0
    else
      0
    end
  end

  def flushdb
    @data.clear
    @expires.clear
  end

  def ping
    'PONG'
  end

  private

  def expired?(key)
    return false unless @expires[key]

    if Time.current > @expires[key]
      @data.delete(key)
      @expires.delete(key)
      true
    else
      false
    end
  end
end

# 併發預約錯誤
class ConcurrentReservationError < StandardError; end

# Redis 連接錯誤
class RedisConnectionError < StandardError; end
