module SolidCacheTestHelpers
  # 清理所有快取內容
  def clear_cache
    Rails.cache.clear
  end

  # 設定測試用的快取值
  def set_cache_value(key, value, options = {})
    Rails.cache.write(key, value, options)
  end

  # 檢查快取鍵是否存在
  def cache_key_exists?(key)
    Rails.cache.exist?(key)
  end

  # 取得快取值
  def get_cache_value(key)
    Rails.cache.read(key)
  end

  # 協助併發測試的方法
  def run_concurrent_test(thread_count: 5)
    results = []
    threads = []
    barrier = Mutex.new
    started = ConditionVariable.new
    ready_count = 0

    thread_count.times do |i|
      threads << Thread.new do
        # 同步起點
        barrier.synchronize do
          ready_count += 1
          if ready_count == thread_count
            started.broadcast
          else
            started.wait(barrier)
          end
        end

        # 執行測試邏輯
        begin
          result = yield(i)
          results << { thread: i, result: result, status: :success }
        rescue StandardError => e
          results << { thread: i, error: e.message, status: :error }
        end
      end
    end

    threads.each(&:join)
    results
  end

  # 等待指定條件為真
  def wait_for_condition(timeout: 1.0, interval: 0.01)
    start_time = Time.current

    loop do
      return true if yield

      return false if Time.current - start_time > timeout

      sleep(interval)
    end
  end
end

RSpec.configure do |config|
  config.include SolidCacheTestHelpers, type: :service
end
