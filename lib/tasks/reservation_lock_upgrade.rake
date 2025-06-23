namespace :reservation_lock do
  desc '驗證 ReservationLockService 升級狀態'
  task verify_upgrade: :environment do
    puts '正在驗證 ReservationLockService 升級...'

    begin
      # 檢查升級狀態
      if ReservationLockService.upgraded?
        puts '✅ ReservationLockService 已成功升級'

        # 顯示升級資訊
        info = ReservationLockService.migration_info
        puts '📋 升級資訊：'
        info.each do |key, value|
          puts "   #{key}: #{value}"
        end

        # 檢查 Redis 連接
        puts "\n🔗 Redis 連接檢查："
        if redis_healthy?
          puts '✅ Redis 連接正常'
          begin
            puts "   Redis 版本: #{Redis.current.info['redis_version']}"
          rescue StandardError
            puts '   無法獲取版本'
          end
        else
          puts '⚠️  Redis 連接異常，但系統仍可正常運行'
        end

        # 檢查新功能
        puts "\n🆕 新功能檢查："
        methods_to_check = %i[locked? force_unlock active_locks]
        methods_to_check.each do |method|
          if ReservationLockService.respond_to?(method)
            puts "✅ #{method} 方法可用"
          else
            puts "❌ #{method} 方法不可用"
          end
        end

        # 檢查舊 API 相容性
        puts "\n🔄 API 相容性檢查："
        if ReservationLockService.respond_to?(:with_lock)
          puts '✅ with_lock 方法相容'
        else
          puts '❌ with_lock 方法不相容'
        end

        puts "\n🎉 升級驗證完成！"

      else
        puts '❌ ReservationLockService 尚未升級'
        exit 1
      end
    rescue StandardError => e
      puts "❌ 升級驗證失敗: #{e.message}"
      puts e.backtrace.first(5) if Rails.env.development?
      exit 1
    end
  end

  desc '測試鎖定服務功能'
  task test_lock_service: :environment do
    puts '正在測試鎖定服務功能...'

    # 在非測試環境中檢查 Redis 可用性
    puts '⚠️  Redis 不可用，將使用測試模式運行' unless Rails.env.test? || redis_healthy?

    restaurant_id = 1
    datetime = 1.hour.from_now
    party_size = 4

    begin
      # 測試基本鎖定功能
      puts '📝 測試基本鎖定功能...'
      ReservationLockService.with_lock(restaurant_id, datetime, party_size) do
        puts '✅ 成功獲取鎖定'
        sleep(0.1) # 模擬一些工作
        puts '✅ 工作完成'
      end
      puts '✅ 鎖定已釋放'

      # 測試鎖定狀態檢查
      puts "\n📝 測試鎖定狀態檢查..."
      locked_before = ReservationLockService.locked?(restaurant_id, datetime, party_size)
      puts "鎖定前狀態: #{locked_before ? '已鎖定' : '未鎖定'}"

      Thread.new do
        ReservationLockService.with_lock(restaurant_id, datetime, party_size) do
          sleep(2) # 持有鎖定 2 秒
        end
      end

      sleep(0.1) # 等待線程獲取鎖定
      locked_during = ReservationLockService.locked?(restaurant_id, datetime, party_size)
      puts "鎖定中狀態: #{locked_during ? '已鎖定' : '未鎖定'}"

      sleep(2.5) # 等待鎖定釋放
      locked_after = ReservationLockService.locked?(restaurant_id, datetime, party_size)
      puts "鎖定後狀態: #{locked_after ? '已鎖定' : '未鎖定'}"

      # 測試活躍鎖定查詢
      puts "\n📝 測試活躍鎖定查詢..."
      active_locks = ReservationLockService.active_locks
      puts "目前活躍鎖定數量: #{active_locks.length}"

      puts "\n🎉 功能測試完成！"
    rescue StandardError => e
      puts "❌ 功能測試失敗: #{e.message}"
      puts e.backtrace.first(5) if Rails.env.development?
      exit 1
    end
  end

  desc '清理所有訂位鎖定（緊急用途）'
  task clear_all_locks: :environment do
    puts '⚠️  正在清理所有訂位鎖定...'

    begin
      if redis_healthy?
        pattern = 'reservation_lock:*'
        keys = Redis.current.keys(pattern)

        if keys.empty?
          puts '📝 沒有找到訂位鎖定'
        else
          puts "📝 找到 #{keys.length} 個訂位鎖定"
          keys.each { |key| Redis.current.del(key) }
          puts "✅ 已清理 #{keys.length} 個鎖定"
        end
      else
        puts '❌ Redis 不可用，無法清理鎖定'
        exit 1
      end
    rescue StandardError => e
      puts "❌ 清理失敗: #{e.message}"
      exit 1
    end
  end

  desc '顯示活躍鎖定資訊'
  task show_active_locks: :environment do
    puts '📋 活躍鎖定資訊：'

    begin
      active_locks = ReservationLockService.active_locks

      if active_locks.empty?
        puts '📝 目前沒有活躍的鎖定'
      else
        puts "📝 找到 #{active_locks.length} 個活躍鎖定："

        active_locks.each_with_index do |lock, index|
          puts "\n🔒 鎖定 ##{index + 1}:"
          puts "   鍵值: #{lock[:key]}"
          puts "   持有者: #{lock[:value]}"
          puts "   剩餘時間: #{lock[:ttl]} 秒"
          puts "   過期時間: #{lock[:expires_at]}" if lock[:expires_at]
        end
      end
    rescue StandardError => e
      puts "❌ 查詢失敗: #{e.message}"
      exit 1
    end
  end

  desc '檢查 Redis 健康狀態'
  task check_redis: :environment do
    puts '🔗 檢查 Redis 健康狀態...'

    begin
      if redis_healthy?
        puts '✅ Redis 連接正常'

        info = Redis.current.info
        puts '📋 Redis 資訊：'
        puts "   版本: #{info['redis_version']}"
        puts "   模式: #{info['redis_mode']}"
        puts "   已使用記憶體: #{info['used_memory_human']}"
        puts "   連接數: #{info['connected_clients']}"
        puts "   運行時間: #{info['uptime_in_seconds']} 秒"

      else
        puts '❌ Redis 連接失敗'
        exit 1
      end
    rescue StandardError => e
      puts "❌ Redis 檢查失敗: #{e.message}"
      exit 1
    end
  end

  private

  def redis_healthy?
    return false unless defined?(Redis.current)

    Redis.current&.ping == 'PONG'
  rescue StandardError
    false
  end
end
