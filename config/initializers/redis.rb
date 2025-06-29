# Redis 配置初始化檔案

# 為 Redis 類別添加 current 類別方法
class Redis
  @current = nil
  
  def self.current
    @current
  end
  
  def self.current=(redis_instance)
    @current = redis_instance
  end
end

if Rails.env.test?
  # 測試環境使用記憶體存儲的 Redis 模擬
  require Rails.root.join('app', 'services', 'enhanced_reservation_lock_service')
  
  # 設定 Redis.current 指向測試模擬
  Redis.current = TestRedis.new
  Rails.logger.info 'Redis.current 設定為 TestRedis (測試環境)'
elsif ENV['CI'] == 'true'
  # CI 環境直接使用最簡單的 mock，不嘗試連接
  require 'ostruct'
  Redis.current = OpenStruct.new(
    ping: 'PONG',
    set: true,
    get: nil,
    del: 0,
    exists?: 0,
    keys: [],
    ttl: -1,
    eval: 0,
    flushdb: 'OK',
    info: { 'redis_version' => 'ci-mock', 'redis_mode' => 'mock' }
  )
  Rails.logger.info 'CI 環境，使用簡單 Redis mock'
else
  # 開發和生產環境配置
  begin
    redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
    
  redis_config = {
      url: redis_url,
      timeout: 1,
      reconnect_attempts: 3
    }
    
    # 初始化 Redis 連接
    Redis.current = Redis.new(redis_config)
    
    # 測試連接
    Redis.current.ping
    Rails.logger.info "Redis.current 初始化成功，連接到: #{redis_url}"
    
  rescue Redis::CannotConnectError, Redis::TimeoutError => e
    Rails.logger.warn "無法連接到 Redis (#{redis_url}): #{e.message}"
    
    if Rails.env.development? || ENV['CI'] == 'true'
      Rails.logger.warn 'Redis 連接失敗，將使用記憶體快取'
      # 在開發環境中，如果 Redis 不可用，使用簡單的記憶體實現
      Redis.current = Class.new do
        def initialize
          @data = {}
          @mutex = Mutex.new
        end
        
        def ping
          'PONG'
        end
        
        def set(key, value, options = {})
          @mutex.synchronize do
            @data[key] = { value: value, expires_at: options[:ex] ? Time.current + options[:ex] : nil }
            true
          end
        end
        
        def get(key)
          @mutex.synchronize do
            entry = @data[key]
            return nil unless entry
            return nil if entry[:expires_at] && Time.current > entry[:expires_at]
            entry[:value]
          end
        end
        
        def del(key)
          @mutex.synchronize do
            @data.delete(key) ? 1 : 0
          end
        end
        
        def exists?(key)
          @mutex.synchronize do
            entry = @data[key]
            return 0 unless entry
            return 0 if entry[:expires_at] && Time.current > entry[:expires_at]
            1
          end
        end
        
        def keys(pattern)
          @mutex.synchronize do
            regex = pattern.gsub('*', '.*')
            @data.keys.select { |k| k.match(/#{regex}/) }
          end
        end
        
        def ttl(key)
          @mutex.synchronize do
            entry = @data[key]
            return -2 unless entry
            return -1 unless entry[:expires_at]
            return -2 if Time.current > entry[:expires_at]
            (entry[:expires_at] - Time.current).to_i
          end
        end
        
        def eval(script, keys:, argv:)
          key = keys.first
          value = argv.first
          if script.include?('redis.call("get", KEYS[1]) == ARGV[1]')
            current_value = get(key)
            current_value == value ? del(key) : 0
          else
            0
          end
        end
        
        def flushdb
          @mutex.synchronize { @data.clear }
        end
        
        def info
          { 'redis_version' => 'memory-mock', 'redis_mode' => 'standalone' }
        end
      end.new
    else
      # 生產環境中，Redis 連接失敗是嚴重錯誤
      raise "Redis 連接失敗: #{e.message}"
    end
  rescue StandardError => e
    Rails.logger.error "Redis 初始化時發生未預期錯誤: #{e.message}"
    raise
  end
end

# 驗證 Redis.current 已正確設定
if defined?(Redis.current) && Redis.current.respond_to?(:ping)
  Rails.logger.info 'Redis.current 配置完成'
else
  Rails.logger.error 'Redis.current 配置失敗'
end