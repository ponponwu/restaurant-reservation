require 'rails_helper'

RSpec.describe SolidCacheReservationLockService, type: :service do
  let(:restaurant_id) { 1 }
  let(:datetime) { Time.zone.parse('2024-12-25 18:00:00') }
  let(:party_size) { 4 }
  let(:service) { described_class }

  before do
    # 清除所有測試快取
    Rails.cache.clear
  end

  after do
    # 清理測試數據
    Rails.cache.clear
  end

  describe '.with_lock' do
    context '成功獲取鎖定' do
      it '執行區塊並釋放鎖定' do
        result = nil
        expect do
          service.with_lock(restaurant_id, datetime, party_size) do
            result = 'success'
          end
        end.not_to raise_error

        expect(result).to eq('success')
        expect(service).not_to be_locked(restaurant_id, datetime, party_size)
      end

      it '記錄獲取和釋放鎖定的日誌' do
        expect(Rails.logger).to receive(:info).with(/獲取 Solid Cache 訂位鎖定/)
        expect(Rails.logger).to receive(:info).with(/釋放 Solid Cache 訂位鎖定/)

        service.with_lock(restaurant_id, datetime, party_size) do
          # 執行某些操作
        end
      end

      it '使用正確的 TTL 設定鎖定' do
        lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)

        service.with_lock(restaurant_id, datetime, party_size) do
          # 在鎖定期間檢查鍵值是否存在
          expect(Rails.cache.exist?(lock_key)).to be true
        end

        # 鎖定釋放後鍵值應該被刪除
        expect(Rails.cache.exist?(lock_key)).to be false
      end
    end

    context '鎖定衝突' do
      it '當鎖定被其他程序持有時拋出錯誤' do
        # 先獲取鎖定
        lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
        Rails.cache.write(lock_key, 'other_process', expires_in: 30.seconds)

        expect do
          service.with_lock(restaurant_id, datetime, party_size) do
            # 這個區塊不應該被執行
          end
        end.to raise_error(ConcurrentReservationError, /有其他客戶正在預訂相同時段/)
      end

      it '記錄無法獲取鎖定的警告' do
        # 預先設置鎖定
        lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
        Rails.cache.write(lock_key, 'other_process', expires_in: 30.seconds)

        expect(Rails.logger).to receive(:warn).with(/無法獲取 Solid Cache 訂位鎖定/)

        expect do
          service.with_lock(restaurant_id, datetime, party_size) do
            # 不會執行
          end
        end.to raise_error(ConcurrentReservationError)
      end

      it '當鎖定不可用時立即拋出錯誤' do
        # 模擬鎖定衝突（不重試）
        allow(Rails.cache).to receive(:write).with(
          anything, anything, hash_including(unless_exist: true)
        ).and_return(false)

        expect do
          service.with_lock(restaurant_id, datetime, party_size) do
            # 不會執行
          end
        end.to raise_error(ConcurrentReservationError)
      end
    end

    context 'Solid Cache 特定行為' do
      it '使用 unless_exist 確保原子性' do
        lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
        service.send(:generate_lock_value)

        expect(Rails.cache).to receive(:write).with(
          lock_key,
          anything,
          hash_including(unless_exist: true, expires_in: SolidCacheReservationLockService::LOCK_TIMEOUT)
        ).and_return(true)

        service.with_lock(restaurant_id, datetime, party_size) do
          # 測試原子性操作被正確調用
        end
      end

      it '自動處理 TTL 過期' do
        lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)

        # 設定一個很短的 TTL
        Rails.cache.write(lock_key, 'test_value', expires_in: 0.1.seconds)

        expect(service.locked?(restaurant_id, datetime, party_size)).to be true

        # 等待過期
        sleep(0.2)

        expect(service.locked?(restaurant_id, datetime, party_size)).to be false
      end

      it 'compare-and-delete 安全釋放機制' do
        lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
        our_value = 'our_lock_value'
        other_value = 'other_lock_value'

        # 設定其他程序的鎖定值
        Rails.cache.write(lock_key, other_value, expires_in: 30.seconds)

        # 嘗試用我們的值釋放（應該失敗）
        result = service.send(:release_lock, lock_key, our_value)
        expect(result).to be false

        # 鎖定應該仍然存在
        expect(Rails.cache.read(lock_key)).to eq(other_value)
      end
    end

    context '異常處理' do
      it '即使區塊拋出異常也要釋放鎖定' do
        expect do
          service.with_lock(restaurant_id, datetime, party_size) do
            raise StandardError, '測試異常'
          end
        end.to raise_error(StandardError, '測試異常')

        # 確保鎖定已被釋放
        expect(service).not_to be_locked(restaurant_id, datetime, party_size)
      end

      it '處理快取服務不可用的情況' do
        allow(Rails.cache).to receive(:write).and_raise(StandardError, 'Cache unavailable')

        expect do
          service.with_lock(restaurant_id, datetime, party_size) do
            # 不會執行
          end
        end.to raise_error(ConcurrentReservationError)
      end
    end
  end

  describe '.locked?' do
    it '當沒有鎖定時返回 false' do
      expect(service).not_to be_locked(restaurant_id, datetime, party_size)
    end

    it '當有鎖定時返回 true' do
      lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
      Rails.cache.write(lock_key, 'test_value', expires_in: 30.seconds)

      expect(service).to be_locked(restaurant_id, datetime, party_size)
    end

    it '當鎖定過期時返回 false' do
      lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
      Rails.cache.write(lock_key, 'test_value', expires_in: 0.1.seconds)

      expect(service).to be_locked(restaurant_id, datetime, party_size)

      sleep(0.2)

      expect(service).not_to be_locked(restaurant_id, datetime, party_size)
    end

    it '處理檢查錯誤並返回 false' do
      allow(Rails.cache).to receive(:exist?).and_raise(StandardError, 'Cache error')
      expect(Rails.logger).to receive(:error).with(/檢查 Solid Cache 鎖定狀態失敗/)

      expect(service.locked?(restaurant_id, datetime, party_size)).to be false
    end
  end

  describe '.force_unlock' do
    it '強制釋放存在的鎖定' do
      lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
      Rails.cache.write(lock_key, 'test_value', expires_in: 30.seconds)

      expect(service).to be_locked(restaurant_id, datetime, party_size)

      result = service.force_unlock(restaurant_id, datetime, party_size)

      expect(result).to be_truthy
      expect(service).not_to be_locked(restaurant_id, datetime, party_size)
    end

    it '對不存在的鎖定返回 false' do
      result = service.force_unlock(restaurant_id, datetime, party_size)
      # Rails.cache.delete 對不存在的鍵會返回 false
      expect(result).to be false
    end

    it '記錄強制釋放的日誌' do
      expect(Rails.logger).to receive(:info).with(/強制釋放 Solid Cache 鎖定/)

      service.force_unlock(restaurant_id, datetime, party_size)
    end

    it '處理強制釋放錯誤' do
      allow(Rails.cache).to receive(:delete).and_raise(StandardError, 'Cache error')
      expect(Rails.logger).to receive(:error).with(/強制釋放 Solid Cache 鎖定失敗/)

      result = service.force_unlock(restaurant_id, datetime, party_size)
      expect(result).to be false
    end
  end

  describe '.active_locks' do
    it '返回空陣列並記錄說明' do
      expect(Rails.logger).to receive(:info).with(/Solid Cache 不支援列舉所有鍵值/)

      result = service.active_locks
      expect(result).to eq([])
    end

    it '處理查詢錯誤' do
      allow(Rails.logger).to receive(:info).and_raise(StandardError, 'Logger error')
      expect(Rails.logger).to receive(:error).with(/獲取活躍 Solid Cache 鎖定失敗/)

      result = service.active_locks
      expect(result).to eq([])
    end
  end

  describe '併發測試' do
    it '防止多個程序同時獲取相同鎖定' do
      results = run_concurrent_test(thread_count: 5) do |thread_id|
        service.with_lock(restaurant_id, datetime, party_size) do
          sleep(0.1) # 持有鎖定 100 毫秒
          "Thread #{thread_id} success"
        end
      end

      # 分析結果
      successful_results = results.select { |r| r[:status] == :success }
      failed_results = results.select { |r| r[:status] == :error }

      puts "Results: #{results}"
      puts "Successful: #{successful_results.length}, Failed: #{failed_results.length}"

      # 在正確的鎖定實現中，應該只有一個線程成功
      expect(successful_results.length).to eq(1)
      expect(failed_results.length).to eq(4)

      # 檢查失敗的原因都是併發錯誤
      failed_results.each do |result|
        expect(result[:error]).to include('有其他客戶正在預訂相同時段')
      end
    end

    it '不同資源的鎖定不會互相影響' do
      datetime2 = datetime + 1.hour
      results = []

      threads = [
        Thread.new do
          service.with_lock(restaurant_id, datetime, party_size) do
            results << 'resource1_locked'
            sleep(0.1)
          end
        end,
        Thread.new do
          service.with_lock(restaurant_id, datetime2, party_size) do
            results << 'resource2_locked'
            sleep(0.1)
          end
        end
      ]

      threads.each(&:join)

      expect(results).to include('resource1_locked', 'resource2_locked')
      expect(results.length).to eq(2)
    end
  end

  describe '立即失敗行為' do
    it '當鎖定已存在時立即失敗' do
      lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)

      # 預先設定鎖定
      Rails.cache.write(lock_key, 'existing_lock', expires_in: 30.seconds)

      expect do
        service.with_lock(restaurant_id, datetime, party_size) do
          # 不會執行
        end
      end.to raise_error(ConcurrentReservationError, /有其他客戶正在預訂相同時段/)
    end

    it '不會重試或等待鎖定釋放' do
      allow(Rails.cache).to receive(:write).and_return(false)

      # 不應該調用 sleep（沒有重試機制）
      expect(service).not_to receive(:sleep)

      expect do
        service.with_lock(restaurant_id, datetime, party_size) do
          # 不會執行
        end
      end.to raise_error(ConcurrentReservationError)
    end
  end

  describe '效能測試' do
    it '單次鎖定操作應在合理時間內完成' do
      time = Benchmark.measure do
        service.with_lock(restaurant_id, datetime, party_size) do
          # 模擬少量工作
          sleep(0.01)
        end
      end

      # 鎖定本身的開銷應該很小（除了工作時間 0.01s）
      expect(time.real).to be < 0.05 # 50ms 內完成
    end

    it '連續鎖定操作效能穩定' do
      times = []

      10.times do |i|
        time = Benchmark.measure do
          service.with_lock(restaurant_id, Time.current + i.hours, party_size) do
            sleep(0.001) # 1ms 工作
          end
        end
        times << time.real
      end

      # 平均時間應該合理
      avg_time = times.sum / times.length
      expect(avg_time).to be < 0.02 # 20ms 平均

      # 時間變異應該不大（最大不超過平均的 3 倍）
      max_time = times.max
      expect(max_time).to be < (avg_time * 3)
    end
  end

  describe 'private methods' do
    describe '.generate_lock_key' do
      it '生成一致的鎖定鍵' do
        key1 = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
        key2 = service.send(:generate_lock_key, restaurant_id, datetime, party_size)

        expect(key1).to eq(key2)
        expect(key1).to include('reservation_lock')
        expect(key1).to include(restaurant_id.to_s)
        expect(key1).to include(party_size.to_s)
        expect(key1).to include(datetime.strftime('%Y%m%d_%H%M'))
      end

      it '不同參數生成不同鍵' do
        key1 = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
        key2 = service.send(:generate_lock_key, restaurant_id + 1, datetime, party_size)
        key3 = service.send(:generate_lock_key, restaurant_id, datetime + 1.hour, party_size)
        key4 = service.send(:generate_lock_key, restaurant_id, datetime, party_size + 1)

        expect([key1, key2, key3, key4].uniq.length).to eq(4)
      end
    end

    describe '.generate_lock_value' do
      it '每次生成唯一的鎖定值' do
        value1 = service.send(:generate_lock_value)
        value2 = service.send(:generate_lock_value)

        expect(value1).not_to eq(value2)
        expect(value1).to include(Socket.gethostname)
        expect(value1).to include(Process.pid.to_s)
        expect(value1).to include(Thread.current.object_id.to_s)
      end

      it '鎖定值包含識別資訊' do
        value = service.send(:generate_lock_value)

        expect(value).to include(Socket.gethostname)
        expect(value).to include(Process.pid.to_s)
        expect(value).to include(Thread.current.object_id.to_s)
        expect(value).to match(/\d+\.\d+/) # 時間戳
      end
    end

    describe '.release_lock' do
      let(:lock_key) { service.send(:generate_lock_key, restaurant_id, datetime, party_size) }
      let(:lock_value) { 'test_lock_value' }

      it '只有持有者能釋放鎖定' do
        Rails.cache.write(lock_key, lock_value, expires_in: 30.seconds)

        result = service.send(:release_lock, lock_key, lock_value)
        expect(result).to be_truthy
        expect(Rails.cache.exist?(lock_key)).to be false
      end

      it '非持有者無法釋放鎖定' do
        Rails.cache.write(lock_key, 'other_value', expires_in: 30.seconds)

        result = service.send(:release_lock, lock_key, lock_value)
        expect(result).to be false
        expect(Rails.cache.exist?(lock_key)).to be true
      end

      it '鎖定不存在時返回 false' do
        result = service.send(:release_lock, lock_key, lock_value)
        expect(result).to be false
      end
    end
  end
end
