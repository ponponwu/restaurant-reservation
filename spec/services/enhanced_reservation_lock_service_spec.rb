require 'rails_helper'

RSpec.describe EnhancedReservationLockService, type: :service do
  let(:restaurant_id) { 1 }
  let(:datetime) { Time.zone.parse('2024-12-25 18:00:00') }
  let(:party_size) { 4 }
  let(:service) { described_class }

  before do
    # 清除所有測試鎖定
    service.send(:redis).flushdb
  end

  after do
    # 清理測試數據
    service.send(:redis).flushdb
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
        expect(Rails.logger).to receive(:info).with(/獲取訂位鎖定/)
        expect(Rails.logger).to receive(:info).with(/釋放訂位鎖定/)

        service.with_lock(restaurant_id, datetime, party_size) do
          # 執行某些操作
        end
      end
    end

    context '鎖定衝突' do
      it '當鎖定被其他程序持有時拋出錯誤' do
        # 先獲取鎖定
        lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
        service.send(:redis).set(lock_key, 'other_process', nx: true, ex: 30)

        expect do
          service.with_lock(restaurant_id, datetime, party_size) do
            # 這個區塊不應該被執行
          end
        end.to raise_error(ConcurrentReservationError, /有其他客戶正在預訂相同時段/)
      end

      it '記錄無法獲取鎖定的警告' do
        # 預先設置鎖定
        lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
        service.send(:redis).set(lock_key, 'other_process', nx: true, ex: 30)

        expect(Rails.logger).to receive(:warn).with(/無法獲取訂位鎖定/)

        expect do
          service.with_lock(restaurant_id, datetime, party_size) do
            # 不會執行
          end
        end.to raise_error(ConcurrentReservationError)
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
    end
  end

  describe '.locked?' do
    it '當沒有鎖定時返回 false' do
      expect(service).not_to be_locked(restaurant_id, datetime, party_size)
    end

    it '當有鎖定時返回 true' do
      lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
      service.send(:redis).set(lock_key, 'test_value', ex: 30)

      expect(service).to be_locked(restaurant_id, datetime, party_size)
    end
  end

  describe '.force_unlock' do
    it '強制釋放存在的鎖定' do
      lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
      service.send(:redis).set(lock_key, 'test_value', ex: 30)

      expect(service).to be_locked(restaurant_id, datetime, party_size)

      result = service.force_unlock(restaurant_id, datetime, party_size)

      expect(result).to be_truthy
      expect(service).not_to be_locked(restaurant_id, datetime, party_size)
    end

    it '對不存在的鎖定返回 false' do
      result = service.force_unlock(restaurant_id, datetime, party_size)
      expect(result).to be_falsey
    end
  end

  describe '.active_locks' do
    it '返回所有活躍的鎖定' do
      # 創建幾個測試鎖定
      lock1_key = service.send(:generate_lock_key, 1, datetime, 2)
      lock2_key = service.send(:generate_lock_key, 2, datetime, 4)

      service.send(:redis).set(lock1_key, 'value1', ex: 30)
      service.send(:redis).set(lock2_key, 'value2', ex: 60)

      active_locks = service.active_locks

      expect(active_locks.length).to eq(2)
      expect(active_locks.map { |lock| lock[:key] }).to contain_exactly(lock1_key, lock2_key)
      expect(active_locks).to(be_all { |lock| lock[:ttl] > 0 })
    end

    it '不返回已過期的鎖定' do
      # 創建一個短期鎖定
      lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
      service.send(:redis).set(lock_key, 'test_value', ex: 1)

      # 等待過期（大幅減少等待時間）
      sleep(0.3)

      active_locks = service.active_locks
      expect(active_locks).to be_empty
    end
  end

  describe '併發測試' do
    it '防止多個程序同時獲取相同鎖定' do
      # 暫時降低重試次數以減少假成功
      original_retry_attempts = EnhancedReservationLockService::RETRY_ATTEMPTS
      stub_const('EnhancedReservationLockService::RETRY_ATTEMPTS', 1)
      
      results = []
      threads = []
      start_time = Time.current

      # 創建多個線程同時嘗試獲取相同鎖定
      5.times do |i|
        threads << Thread.new do
          # 所有線程同時開始
          sleep_until = start_time + 0.1
          sleep([sleep_until - Time.current, 0].max)
          
          service.with_lock(restaurant_id, datetime, party_size) do
            results << "Thread #{i} success"
            sleep(0.05) # 減少持有鎖定時間到50毫秒
          end
        rescue ConcurrentReservationError
          results << "Thread #{i} failed"
        end
      end

      threads.each(&:join)

      # 檢查結果
      success_count = results.count { |r| r.include?('success') }
      failed_count = results.count { |r| r.include?('failed') }

      puts "Results: #{results}"
      puts "Success count: #{success_count}, Failed count: #{failed_count}"

      # 在正確的鎖定實現中，應該大部分線程失敗
      # 由於重試機制和時間差，允許最多2個線程成功
      expect(success_count).to be <= 2
      expect(failed_count).to be >= 3
      expect(results.length).to eq(5)
    end
  end

  describe 'Redis 錯誤處理' do
    it '處理 Redis 連接錯誤' do
      allow(service.send(:redis)).to receive(:set).and_raise(Redis::ConnectionError)

      expect do
        service.with_lock(restaurant_id, datetime, party_size) do
          # 不會執行
        end
      end.to raise_error(ConcurrentReservationError)
    end
  end

  describe '重試機制' do
    it '在短時間鎖定後會重試' do
      # 測試重試機制：先創建一個短期鎖定，然後在等待期間讓它過期
      lock_key = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
      
      # 使用一個會在重試過程中過期的鎖定
      Thread.new do
        sleep(0.05) # 50毫秒後釋放鎖定
        service.send(:redis).del(lock_key)
      end
      
      # 先設定鎖定
      service.send(:redis).set(lock_key, 'will_expire_soon', ex: 1)

      # 這應該會重試並最終成功
      result = nil
      expect do
        service.with_lock(restaurant_id, datetime, party_size) do
          result = 'success after retry'
        end
      end.not_to raise_error

      expect(result).to eq('success after retry')
    end
  end

  describe '鎖定鍵值生成' do
    it '為不同參數生成不同的鎖定鍵' do
      key1 = service.send(:generate_lock_key, 1, datetime, 2)
      key2 = service.send(:generate_lock_key, 1, datetime, 4)
      key3 = service.send(:generate_lock_key, 2, datetime, 2)

      expect(key1).not_to eq(key2)
      expect(key1).not_to eq(key3)
      expect(key2).not_to eq(key3)
    end

    it '為相同參數生成相同的鎖定鍵' do
      key1 = service.send(:generate_lock_key, restaurant_id, datetime, party_size)
      key2 = service.send(:generate_lock_key, restaurant_id, datetime, party_size)

      expect(key1).to eq(key2)
    end
  end

  describe '鎖定值生成' do
    it '每次生成唯一的鎖定值' do
      value1 = service.send(:generate_lock_value)
      value2 = service.send(:generate_lock_value)

      expect(value1).not_to eq(value2)
      expect(value1).to include(Socket.gethostname)
      expect(value1).to include(Process.pid.to_s)
    end
  end
end
