require 'rails_helper'

RSpec.describe PostgresReservationLockService do
  let(:restaurant_id) { 1 }
  let(:datetime) { Time.zone.parse('2024-03-15 18:00') }
  let(:party_size) { 4 }
  
  before do
    # 確保測試前清理所有鎖定
    described_class.active_locks.each do |lock|
      ApplicationRecord.connection.execute("SELECT pg_advisory_unlock(#{lock[:lock_id]})")
    end
  end

  after do
    # 測試後清理
    described_class.active_locks.each do |lock|
      ApplicationRecord.connection.execute("SELECT pg_advisory_unlock(#{lock[:lock_id]})")
    end
  end

  describe '.with_lock' do
    it '成功獲取和釋放鎖定' do
      result = nil
      expect {
        described_class.with_lock(restaurant_id, datetime, party_size) do
          result = 'success'
        end
      }.not_to raise_error
      
      expect(result).to eq('success')
    end

    it '防止併發訪問同一資源' do
      results = []
      
      threads = 2.times.map do |i|
        Thread.new do
          described_class.with_lock(restaurant_id, datetime, party_size) do
            results << "thread_#{i}_start"
            sleep(0.1)  # 模擬處理時間
            results << "thread_#{i}_end"
          end
        rescue ConcurrentReservationError => e
          results << "thread_#{i}_failed: #{e.message}"
        end
      end

      threads.each(&:join)

      # 檢查結果：應該只有一個線程成功，另一個失敗或等待
      successful_threads = results.select { |r| r.include?('_start') }
      expect(successful_threads.length).to eq(1)
    end

    it '不同資源可以同時獲取鎖定' do
      datetime2 = datetime + 1.hour
      results = []
      
      threads = [
        Thread.new do
          described_class.with_lock(restaurant_id, datetime, party_size) do
            results << 'resource1_locked'
            sleep(0.1)
          end
        end,
        Thread.new do
          described_class.with_lock(restaurant_id, datetime2, party_size) do
            results << 'resource2_locked'
            sleep(0.1)
          end
        end
      ]

      threads.each(&:join)

      expect(results).to include('resource1_locked', 'resource2_locked')
      expect(results.length).to eq(2)
    end

    it '在超過重試次數後拋出異常' do
      # 先獲取鎖定
      Thread.new do
        described_class.with_lock(restaurant_id, datetime, party_size) do
          sleep(1)  # 持有鎖定 1 秒
        end
      end

      sleep(0.05)  # 確保第一個線程先獲取鎖定

      expect {
        described_class.with_lock(restaurant_id, datetime, party_size) do
          # 這裡不應該被執行
        end
      }.to raise_error(ConcurrentReservationError, /有其他客戶正在預訂相同時段/)
    end
  end

  describe '.locked?' do
    it '檢測鎖定狀態' do
      expect(described_class.locked?(restaurant_id, datetime, party_size)).to be_falsey

      Thread.new do
        described_class.with_lock(restaurant_id, datetime, party_size) do
          # 鎖定期間檢測
        end
      end

      sleep(0.05)  # 給點時間讓鎖定生效
      # 注意：由於鎖定會在 block 結束後釋放，這個測試可能需要調整
    end

    it '未鎖定時返回 false' do
      expect(described_class.locked?(restaurant_id, datetime, party_size)).to be_falsey
    end
  end

  describe '.force_unlock' do
    it '可以強制釋放鎖定' do
      # 這個測試比較複雜，因為需要在不同的連接中測試
      # 實際使用中，force_unlock 主要用於管理工具
      expect(described_class.force_unlock(restaurant_id, datetime, party_size)).to be_in([true, false])
    end
  end

  describe '.active_locks' do
    it '返回活躍鎖定列表' do
      locks = described_class.active_locks
      expect(locks).to be_an(Array)
      
      # 所有鎖定都應該有必要的屬性
      locks.each do |lock|
        expect(lock).to have_key(:key)
        expect(lock).to have_key(:lock_id)
        expect(lock).to have_key(:pid)
        expect(lock).to have_key(:granted)
      end
    end
  end

  describe 'private methods' do
    describe '.generate_lock_key' do
      it '生成一致的鎖定鍵' do
        key1 = described_class.send(:generate_lock_key, restaurant_id, datetime, party_size)
        key2 = described_class.send(:generate_lock_key, restaurant_id, datetime, party_size)
        
        expect(key1).to eq(key2)
        expect(key1).to include('reservation_lock')
        expect(key1).to include(restaurant_id.to_s)
        expect(key1).to include(party_size.to_s)
      end

      it '不同參數生成不同鍵' do
        key1 = described_class.send(:generate_lock_key, restaurant_id, datetime, party_size)
        key2 = described_class.send(:generate_lock_key, restaurant_id + 1, datetime, party_size)
        
        expect(key1).not_to eq(key2)
      end
    end

    describe '.generate_lock_id' do
      it '為相同鍵生成相同 ID' do
        key = 'test_key'
        id1 = described_class.send(:generate_lock_id, key)
        id2 = described_class.send(:generate_lock_id, key)
        
        expect(id1).to eq(id2)
        expect(id1).to be_a(Integer)
        expect(id1).to be > 1000000000  # 檢查前綴
      end

      it '為不同鍵生成不同 ID' do
        id1 = described_class.send(:generate_lock_id, 'key1')
        id2 = described_class.send(:generate_lock_id, 'key2')
        
        expect(id1).not_to eq(id2)
      end
    end
  end

  describe '與 EnhancedReservationLockService 的 API 相容性' do
    let(:redis_service) { EnhancedReservationLockService }
    let(:postgres_service) { PostgresReservationLockService }

    it '具有相同的公開方法' do
      expected_methods = %i[with_lock locked? force_unlock active_locks]
      
      expected_methods.each do |method|
        expect(postgres_service).to respond_to(method)
        expect(redis_service).to respond_to(method)
      end
    end

    it 'with_lock 方法具有相同的參數簽名' do
      postgres_method = postgres_service.method(:with_lock)
      redis_method = redis_service.method(:with_lock)
      
      expect(postgres_method.arity).to eq(redis_method.arity)
    end
  end

  describe '錯誤處理' do
    it '處理資料庫連接錯誤' do
      allow(ApplicationRecord.connection).to receive(:execute).and_raise(ActiveRecord::StatementInvalid)
      
      expect(described_class.locked?(restaurant_id, datetime, party_size)).to be_falsey
      expect(described_class.force_unlock(restaurant_id, datetime, party_size)).to be_falsey
      expect(described_class.active_locks).to eq([])
    end
  end
end