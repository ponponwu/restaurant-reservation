require 'rails_helper'

RSpec.describe Reservation, type: :model do
  let(:restaurant) { create(:restaurant) }
  let(:reservation) { create(:reservation, restaurant: restaurant) }

  describe 'cancellation token generation' do
    it 'automatically generates cancellation_token on creation' do
      new_reservation = create(:reservation, restaurant: restaurant)
      expect(new_reservation.cancellation_token).to be_present
      expect(new_reservation.cancellation_token).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it 'ensures cancellation_token uniqueness' do
      reservation1 = create(:reservation, restaurant: restaurant)
      reservation2 = create(:reservation, restaurant: restaurant)
      
      expect(reservation1.cancellation_token).not_to eq(reservation2.cancellation_token)
    end
  end

  describe '#can_cancel_by_customer?' do
    context 'when reservation is pending' do
      before { reservation.update!(status: :pending) }

      it 'returns true when reservation is in future' do
        reservation.update!(reservation_datetime: 2.hours.from_now)
        expect(reservation.can_cancel_by_customer?).to be true
      end

      it 'returns false when reservation time has passed' do
        reservation.update!(reservation_datetime: 1.hour.ago)
        expect(reservation.can_cancel_by_customer?).to be false
      end
    end

    context 'when reservation is confirmed' do
      before { reservation.update!(status: :confirmed) }

      it 'returns true when in future' do
        reservation.update!(reservation_datetime: 2.hours.from_now)
        expect(reservation.can_cancel_by_customer?).to be true
      end
    end

    context 'when reservation is cancelled' do
      before { reservation.update!(status: :cancelled) }

      it 'returns false' do
        expect(reservation.can_cancel_by_customer?).to be false
      end
    end
  end

  describe '#cancel_by_customer!' do
    before do
      reservation.update!(
        status: :confirmed, 
        reservation_datetime: 2.hours.from_now
      )
    end

    context 'when cancellation is allowed' do
      it 'successfully cancels the reservation' do
        result = reservation.cancel_by_customer!('個人行程異動')
        
        expect(result).to be true
        expect(reservation.reload.status).to eq('cancelled')
        expect(reservation.cancelled_by).to eq('customer')
        expect(reservation.cancelled_at).to be_present
        expect(reservation.cancellation_reason).to eq('個人行程異動')
        expect(reservation.cancellation_method).to eq('online_self_service')
      end

      it 'updates notes with cancellation info' do
        original_notes = '特殊需求：靠窗座位'
        reservation.update!(notes: original_notes)
        
        reservation.cancel_by_customer!('時間衝突')
        
        expect(reservation.notes).to include(original_notes)
        expect(reservation.notes).to include('客戶取消於')
        expect(reservation.notes).to include('原因：時間衝突')
      end

      it 'works without cancellation reason' do
        result = reservation.cancel_by_customer!
        
        expect(result).to be true
        expect(reservation.reload.cancellation_reason).to be_nil
        expect(reservation.notes).to include('客戶取消於')
        expect(reservation.notes).not_to include('原因：')
      end
    end

    context 'when cancellation is not allowed' do
      it 'returns false for past reservations' do
        reservation.update!(reservation_datetime: 1.hour.ago)
        
        result = reservation.cancel_by_customer!('遲到了')
        
        expect(result).to be false
        expect(reservation.reload.status).not_to eq('cancelled')
      end

      it 'returns false for already cancelled reservations' do
        reservation.update!(status: :cancelled)
        
        result = reservation.cancel_by_customer!('再次取消')
        
        expect(result).to be false
      end
    end
  end

  describe '#cancel_by_admin!' do
    let(:admin_user) { double('User', name: '管理員小王') }
    
    before do
      reservation.update!(
        status: :confirmed,
        reservation_datetime: 2.hours.from_now
      )
    end

    it 'successfully cancels with admin tracking' do
      result = reservation.cancel_by_admin!(admin_user, '客戶要求退款')
      
      expect(result).to be true
      expect(reservation.reload.status).to eq('cancelled')
      expect(reservation.cancelled_by).to eq('admin:管理員小王')
      expect(reservation.cancelled_at).to be_present
      expect(reservation.cancellation_reason).to eq('客戶要求退款')
      expect(reservation.cancellation_method).to eq('admin_interface')
      expect(reservation.notes).to include('管理員管理員小王取消於')
    end
  end

  describe '#cancellation_url' do
    it 'generates correct cancellation URL' do
      url = reservation.cancellation_url
      expect(url).to include(restaurant.slug)
      expect(url).to include(reservation.cancellation_token)
      expect(url).to include('/reservations/')
    end

    it 'returns nil when cancellation_token is blank' do
      # 使用 allow 來模擬 cancellation_token 為空的情況
      allow(reservation).to receive(:cancellation_token).and_return(nil)
      expect(reservation.cancellation_url).to be_nil
    end
  end

  describe '#cancellation_deadline' do
    it 'returns the reservation datetime as deadline' do
      reservation.update!(reservation_datetime: Time.current + 4.hours)
      
      deadline = reservation.cancellation_deadline
      expected_deadline = reservation.reservation_datetime
      
      expect(deadline).to eq(expected_deadline)
    end
  end

  # 測試快取清除機制
  describe 'cache clearing' do
    it 'clears availability cache after creation' do
      cache_key = "availability_status:#{restaurant.id}:#{Date.current}:4:v3"
      Rails.cache.write(cache_key, { test: 'data' })
      
      expect(Rails.cache.read(cache_key)).to be_present
      
      # 創建新訂位應該清除快取
      create(:reservation, restaurant: restaurant)
      
      expect(Rails.cache.read(cache_key)).to be_nil
    end
    
    it 'clears availability cache after status update' do
      cache_key = "availability_status:#{restaurant.id}:#{Date.current}:2:v3"
      Rails.cache.write(cache_key, { test: 'data' })
      
      expect(Rails.cache.read(cache_key)).to be_present
      
      # 更新訂位狀態應該清除快取
      reservation.update!(status: :cancelled)
      
      expect(Rails.cache.read(cache_key)).to be_nil
    end
    
    it 'clears availability cache after deletion' do
      cache_key = "availability_status:#{restaurant.id}:#{Date.current}:2:v3"
      Rails.cache.write(cache_key, { test: 'data' })
      
      expect(Rails.cache.read(cache_key)).to be_present
      
      # 刪除訂位應該清除快取
      reservation.destroy
      
      expect(Rails.cache.read(cache_key)).to be_nil
    end
    
    it 'clears multiple party size cache keys' do
      # 設定多個不同人數的快取
      (1..5).each do |party_size|
        cache_key = "availability_status:#{restaurant.id}:#{Date.current}:#{party_size}:v3"
        Rails.cache.write(cache_key, { party_size: party_size })
      end
      
      # 創建訂位應該清除所有相關快取
      create(:reservation, restaurant: restaurant)
      
      (1..5).each do |party_size|
        cache_key = "availability_status:#{restaurant.id}:#{Date.current}:#{party_size}:v3"
        expect(Rails.cache.read(cache_key)).to be_nil
      end
    end
  end

  describe '#skip_blacklist_validation' do
    let(:restaurant) { create(:restaurant) }
    let(:blacklisted_phone) { '0987654321' }
    
    before do
      # 創建黑名單記錄
      create(:blacklist, 
             restaurant: restaurant, 
             customer_phone: blacklisted_phone,
             reason: 'Test reason')
    end

    context 'when skip_blacklist_validation is false (default)' do
      it 'validates blacklist and prevents creation' do
        reservation = build(:reservation, 
                           restaurant: restaurant,
                           customer_phone: blacklisted_phone)
        
        expect(reservation.valid?).to be false
        expect(reservation.errors[:base]).to include('訂位失敗，請聯繫餐廳')
      end
    end

    context 'when skip_blacklist_validation is true' do
      it 'skips blacklist validation and allows creation' do
        reservation = build(:reservation, 
                           restaurant: restaurant,
                           customer_phone: blacklisted_phone)
        reservation.skip_blacklist_validation = true
        
        # 移除其他可能的驗證錯誤，只測試黑名單驗證
        reservation.reservation_datetime = 2.days.from_now
        reservation.adults_count = reservation.party_size
        reservation.children_count = 0
        
        expect(reservation.valid?).to be true
      end
    end

    context 'with normal phone number' do
      let(:normal_phone) { '0912345678' }
      
      it 'allows creation regardless of skip_blacklist_validation setting' do
        reservation1 = build(:reservation, 
                            restaurant: restaurant,
                            customer_phone: normal_phone)
        reservation1.skip_blacklist_validation = false
        
        reservation2 = build(:reservation, 
                            restaurant: restaurant,
                            customer_phone: normal_phone)
        reservation2.skip_blacklist_validation = true
        
        # 修正其他驗證問題
        [reservation1, reservation2].each do |res|
          res.reservation_datetime = 2.days.from_now
          res.adults_count = res.party_size
          res.children_count = 0
        end
        
        expect(reservation1.valid?).to be true
        expect(reservation2.valid?).to be true
      end
    end
  end

  describe 'blacklist validation error message' do
    let(:restaurant) { create(:restaurant) }
    let(:blacklisted_phone) { '0987654321' }
    
    before do
      create(:blacklist, 
             restaurant: restaurant, 
             customer_phone: blacklisted_phone,
             reason: 'Specific blacklist reason')
    end

    it 'shows generic error message instead of specific blacklist details' do
      reservation = build(:reservation, 
                         restaurant: restaurant,
                         customer_phone: blacklisted_phone)
      
      reservation.valid?
      
      expect(reservation.errors[:base]).to include('訂位失敗，請聯繫餐廳')
      expect(reservation.errors.full_messages.join).not_to include('黑名單')
      expect(reservation.errors.full_messages.join).not_to include('Specific blacklist reason')
    end
  end

  describe '#skip_blacklist_validation attribute' do
    it 'has skip_blacklist_validation accessor' do
      reservation = Reservation.new
      
      expect(reservation).to respond_to(:skip_blacklist_validation)
      expect(reservation).to respond_to(:skip_blacklist_validation=)
    end
    
    it 'defaults to nil/false' do
      reservation = Reservation.new
      expect(reservation.skip_blacklist_validation).to be_nil
    end
    
    it 'can be set to true' do
      reservation = Reservation.new
      reservation.skip_blacklist_validation = true
      expect(reservation.skip_blacklist_validation).to be true
    end
  end
end 