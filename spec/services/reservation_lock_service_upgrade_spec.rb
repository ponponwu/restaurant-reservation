require 'rails_helper'

RSpec.describe 'ReservationLockService 升級測試', type: :service do
  let(:restaurant_id) { 1 }
  let(:datetime) { Time.zone.parse('2024-12-25 18:00:00') }
  let(:party_size) { 4 }

  before do
    # 清除所有測試鎖定

    EnhancedReservationLockService.send(:redis).flushdb
  rescue StandardError
    # 忽略 Redis 連接錯誤（測試環境可能沒有 Redis）
  end

  after do
    # 清理測試數據

    EnhancedReservationLockService.send(:redis).flushdb
  rescue StandardError
    # 忽略 Redis 連接錯誤
  end

  describe '向後相容性測試' do
    it '舊的 API 調用仍然有效' do
      result = nil
      expect do
        ReservationLockService.with_lock(restaurant_id, datetime, party_size) do
          result = 'success'
        end
      end.not_to raise_error

      expect(result).to eq('success')
    end

    it '提供升級資訊' do
      info = ReservationLockService.migration_info

      expect(info[:version]).to include('Enhanced Redis')
      expect(info[:backend]).to eq('Redis')
      expect(info[:new_service]).to eq('EnhancedReservationLockService')
    end

    it '確認已升級狀態' do
      expect(ReservationLockService).to be_upgraded
    end
  end

  describe '新功能可用性測試' do
    it '鎖定狀態檢查功能可用' do
      expect(ReservationLockService).to respond_to(:locked?)
    end

    it '強制解鎖功能可用' do
      expect(ReservationLockService).to respond_to(:force_unlock)
    end

    it '活躍鎖定查詢功能可用' do
      expect(ReservationLockService).to respond_to(:active_locks)
    end
  end

  describe '功能委派測試' do
    context 'with_lock 方法' do
      it '正確委派到 EnhancedReservationLockService' do
        expect(EnhancedReservationLockService).to receive(:with_lock)
          .with(restaurant_id, datetime, party_size)
          .and_return('delegated')

        result = ReservationLockService.with_lock(restaurant_id, datetime, party_size)
        expect(result).to eq('delegated')
      end
    end

    context 'locked? 方法' do
      it '正確委派到 EnhancedReservationLockService' do
        expect(EnhancedReservationLockService).to receive(:locked?)
          .with(restaurant_id, datetime, party_size)
          .and_return(true)

        result = ReservationLockService.locked?(restaurant_id, datetime, party_size)
        expect(result).to be_truthy
      end
    end

    context 'force_unlock 方法' do
      it '正確委派到 EnhancedReservationLockService' do
        expect(EnhancedReservationLockService).to receive(:force_unlock)
          .with(restaurant_id, datetime, party_size)
          .and_return(true)

        result = ReservationLockService.force_unlock(restaurant_id, datetime, party_size)
        expect(result).to be_truthy
      end
    end

    context 'active_locks 方法' do
      it '正確委派到 EnhancedReservationLockService' do
        expected_locks = [{ key: 'test', ttl: 30 }]
        expect(EnhancedReservationLockService).to receive(:active_locks)
          .and_return(expected_locks)

        result = ReservationLockService.active_locks
        expect(result).to eq(expected_locks)
      end
    end
  end

  describe '例外處理相容性' do
    it 'ConcurrentReservationError 仍然可用' do
      expect { raise ConcurrentReservationError, '測試' }.to raise_error(ConcurrentReservationError, '測試')
    end

    it 'RedisConnectionError 也可用' do
      expect { raise RedisConnectionError, '測試' }.to raise_error(RedisConnectionError, '測試')
    end
  end

  describe '日誌記錄' do
    it '可以記錄升級資訊' do
      expect(Rails.logger).to receive(:info).at_least(4).times

      ReservationLockService.log_upgrade_info
    end
  end

  describe 'Redis 後端驗證' do
    it '使用 Redis 或 TestRedis 作為後端存儲' do
      # 在測試環境中會使用 TestRedis，在其他環境中使用 Redis
      redis_instance = EnhancedReservationLockService.send(:redis)
      expect(redis_instance).to respond_to(:ping)
      expect(redis_instance).to respond_to(:set)
      expect(redis_instance).to respond_to(:get)
      expect(redis_instance).to respond_to(:del)
    end
  end

  private

  def redis_available?
    Redis.current.ping == 'PONG'
  rescue StandardError
    false
  end
end
