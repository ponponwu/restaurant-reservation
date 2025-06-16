require 'rails_helper'

RSpec.describe Reservation, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"

  # 測試快取清除機制
  describe 'cache clearing' do
    let(:restaurant) { create(:restaurant) }
    let(:reservation) { create(:reservation, restaurant: restaurant) }
    
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
end
