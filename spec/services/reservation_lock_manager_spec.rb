require 'rails_helper'

RSpec.describe ReservationLockManager do
  let(:restaurant_id) { 1 }
  let(:datetime) { Time.zone.parse('2024-03-15 18:00') }
  let(:party_size) { 4 }

  before do
    # 清理快取設定
    Rails.cache.delete('use_postgres_locks')
    
    # 重置環境變數（如果存在）
    @original_env = ENV['USE_POSTGRES_LOCKS']
    ENV.delete('USE_POSTGRES_LOCKS')
  end

  after do
    # 恢復環境變數
    if @original_env
      ENV['USE_POSTGRES_LOCKS'] = @original_env
    else
      ENV.delete('USE_POSTGRES_LOCKS')
    end
    
    # 清理快取設定
    Rails.cache.delete('use_postgres_locks')
  end

  describe '.current_service' do
    context '在測試環境' do
      it '預設使用 PostgreSQL' do
        expect(described_class.current_service).to eq(:postgres)
      end
    end

    context '使用環境變數控制' do
      it '環境變數為 true 時使用 PostgreSQL' do
        ENV['USE_POSTGRES_LOCKS'] = 'true'
        expect(described_class.current_service).to eq(:postgres)
      end

      it '環境變數為 false 時使用 Redis' do
        ENV['USE_POSTGRES_LOCKS'] = 'false'
        expect(described_class.current_service).to eq(:redis)
      end
    end

    context '在開發環境' do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      end

      it '預設使用 Redis' do
        expect(described_class.current_service).to eq(:redis)
      end

      it '可以通過快取切換' do
        Rails.cache.write('use_postgres_locks', true)
        expect(described_class.current_service).to eq(:postgres)
      end
    end
  end

  describe '.with_lock' do
    it '委派給選定的鎖定服務' do
      expect(PostgresReservationLockService).to receive(:with_lock)
        .with(restaurant_id, datetime, party_size)
        .and_yield

      result = nil
      described_class.with_lock(restaurant_id, datetime, party_size) do
        result = 'success'
      end

      expect(result).to eq('success')
    end

    context '使用 Redis 服務' do
      before do
        ENV['USE_POSTGRES_LOCKS'] = 'false'
      end

      it '委派給 Redis 服務' do
        expect(EnhancedReservationLockService).to receive(:with_lock)
          .with(restaurant_id, datetime, party_size)
          .and_yield

        result = nil
        described_class.with_lock(restaurant_id, datetime, party_size) do
          result = 'redis_success'
        end

        expect(result).to eq('redis_success')
      end
    end
  end

  describe '.locked?' do
    it '委派給選定的鎖定服務' do
      expect(PostgresReservationLockService).to receive(:locked?)
        .with(restaurant_id, datetime, party_size)
        .and_return(true)

      result = described_class.locked?(restaurant_id, datetime, party_size)
      expect(result).to be_truthy
    end
  end

  describe '.force_unlock' do
    it '委派給選定的鎖定服務' do
      expect(PostgresReservationLockService).to receive(:force_unlock)
        .with(restaurant_id, datetime, party_size)
        .and_return(true)

      result = described_class.force_unlock(restaurant_id, datetime, party_size)
      expect(result).to be_truthy
    end
  end

  describe '.active_locks' do
    it '委派給選定的鎖定服務' do
      mock_locks = [{ key: 'test_lock', lock_id: 123 }]
      expect(PostgresReservationLockService).to receive(:active_locks)
        .and_return(mock_locks)

      result = described_class.active_locks
      expect(result).to eq(mock_locks)
    end
  end

  describe 'runtime switching methods' do
    before do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
    end

    describe '.switch_to_postgres!' do
      it '切換到 PostgreSQL 並記錄日誌' do
        expect(Rails.logger).to receive(:info).with('切換到 PostgreSQL Advisory Locks')
        
        described_class.switch_to_postgres!
        expect(described_class.current_service).to eq(:postgres)
      end
    end

    describe '.switch_to_redis!' do
      it '切換到 Redis 並記錄日誌' do
        expect(Rails.logger).to receive(:info).with('切換到 Redis Locks')
        
        described_class.switch_to_redis!
        expect(described_class.current_service).to eq(:redis)
      end
    end
  end

  describe '.status_info' do
    it '返回系統狀態資訊' do
      status = described_class.status_info
      
      expect(status).to include(
        :current_service,
        :postgres_available,
        :redis_available,
        :environment,
        :config_source
      )
      
      expect(status[:environment]).to eq('test')
      expect(status[:current_service]).to be_in([:postgres, :redis])
    end

    it '檢查 PostgreSQL 可用性' do
      allow(ApplicationRecord.connection).to receive(:execute).and_return([{}])
      
      status = described_class.status_info
      expect(status[:postgres_available]).to be_truthy
    end

    it '處理 PostgreSQL 連接錯誤' do
      allow(ApplicationRecord.connection).to receive(:execute).and_raise(StandardError)
      
      status = described_class.status_info
      expect(status[:postgres_available]).to be_falsey
    end

    it '檢查 Redis 可用性' do
      mock_redis = double('redis')
      allow(mock_redis).to receive(:ping).and_return('PONG')
      stub_const('Redis', Class.new { def self.current; end })
      allow(Redis).to receive(:current).and_return(mock_redis)
      
      status = described_class.status_info
      expect(status[:redis_available]).to be_truthy
    end
  end

  describe '配置來源檢測' do
    it '正確檢測環境變數來源' do
      ENV['USE_POSTGRES_LOCKS'] = 'true'
      
      status = described_class.status_info
      expect(status[:config_source]).to eq('ENV[USE_POSTGRES_LOCKS]')
    end

    it '檢測 Rails 配置來源' do
      allow(Rails.application.config).to receive(:respond_to?).with(:use_postgres_locks).and_return(true)
      
      status = described_class.status_info
      expect(status[:config_source]).to eq('Rails.config.use_postgres_locks')
    end

    it '在開發環境檢測快取來源' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      
      status = described_class.status_info
      expect(status[:config_source]).to eq('Rails.cache')
    end
  end
end