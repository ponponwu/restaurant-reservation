require 'rails_helper'
require 'concurrent'

RSpec.describe 'Frontend Stress Tests and Edge Cases' do
  let(:restaurant) { create(:restaurant) }
  let(:reservation_period) { create(:reservation_period, restaurant: restaurant) }
  let(:table_group) { create(:table_group, restaurant: restaurant) }
  let(:table) { create(:table, restaurant: restaurant, table_group: table_group) }

  before do
    reservation_period
    table
    restaurant.reservation_policy.update!(reservation_enabled: true)
  end

  describe 'Concurrent booking scenarios' do
    let(:valid_params) do
      {
        reservation: {
          customer_name: '測試客戶',
          customer_phone: '0912345678',
          customer_email: 'test@example.com'
        },
        date: Date.tomorrow.strftime('%Y-%m-%d'),
        time_slot: '18:00',
        adults: 2,
        children: 0,
        reservation_period_id: reservation_period.id
      }
    end

    it 'handles concurrent reservations for same time slot' do
      # 清空所有現有預約
      Reservation.delete_all

      # 模擬兩個用戶同時預約同一時段
      threads = []
      reservation_results = Concurrent::Array.new # 使用線程安全的數組

      2.times do |i|
        threads << Thread.new do
          params = valid_params.deep_dup
          params[:reservation][:customer_phone] = "091234567#{i}"
          params[:reservation][:customer_email] = "test#{i}@example.com"

          begin
            # 在新的資料庫連接中執行，確保併發測試的準確性
            ActiveRecord::Base.connection_pool.with_connection do
              post restaurant_reservations_path(restaurant.slug), params: params
              reservation_results << { success: response.status == 302, response: response }
            end
          rescue StandardError => e
            reservation_results << { success: false, error: e.message }
          end
        end
      end

      threads.each(&:join)

      # 應該只有一個成功，另一個失敗或被重定向
      successful_reservations = reservation_results.count { |r| r[:success] }
      expect(successful_reservations).to be <= 1

      # 資料庫中應該只有一個訂位記錄
      expect(Reservation.count).to eq(1)
    end

    it 'handles high-frequency API calls' do
      # 模擬短時間內大量API呼叫
      start_time = Time.current

      10.times do
        get "/restaurants/#{restaurant.slug}/reservations/availability_status",
            params: { party_size: 2 }

        expect(response).to have_http_status(:success)
      end

      end_time = Time.current
      total_time = end_time - start_time

      # 應該在合理時間內完成（包含快取效果）
      expect(total_time).to be < 5.seconds
    end
  end

  describe 'Database constraint violations' do
    it 'handles duplicate reservations gracefully' do
      # 清空所有現有預約
      Reservation.delete_all

      # 建立第一個訂位
      create(:reservation,
             restaurant: restaurant,
             customer_phone: '0912345678',
             reservation_datetime: Date.tomorrow + 18.hours,
             table: table)

      # 嘗試建立完全相同的訂位
      params = {
        reservation: {
          customer_name: '重複客戶',
          customer_phone: '0912345678',
          customer_email: 'duplicate@example.com'
        },
        date: Date.tomorrow.strftime('%Y-%m-%d'),
        time_slot: '18:00',
        adults: 2,
        children: 0,
        reservation_period_id: reservation_period.id
      }

      post restaurant_reservations_path(restaurant.slug), params: params

      # 應該優雅地處理，不會崩潰
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Reservation.count).to eq(1) # 還是只有一個訂位
    end
  end

  describe 'Large party size handling' do
    before do
      # 創建多個桌位支持大團體
      5.times do |i|
        create(:table,
               restaurant: restaurant,
               table_group: table_group,
               capacity: 8,
               max_capacity: 8,
               table_number: "Large-#{i + 1}")
      end
    end

    it 'handles maximum party size reservations' do
      large_party_params = {
        reservation: {
          customer_name: '大團體客戶',
          customer_phone: '0912345678',
          customer_email: 'large@example.com'
        },
        date: Date.tomorrow.strftime('%Y-%m-%d'),
        time_slot: '18:00',
        adults: 20,
        children: 5,
        reservation_period_id: reservation_period.id
      }

      post restaurant_reservations_path(restaurant.slug), params: large_party_params

      if response.status == 302 # 成功
        reservation = Reservation.last
        expect(reservation.party_size).to eq(25)
        expect(reservation.table_combination).to be_present
      else # 失敗但應該有適當錯誤
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'Date and time edge cases' do
    it 'handles year boundary dates' do
      # 測試跨年日期
      new_year_date = Date.new(Date.current.year + 1, 1, 1)

      params = {
        reservation: {
          customer_name: '跨年客戶',
          customer_phone: '0912345678',
          customer_email: 'newyear@example.com'
        },
        date: new_year_date.strftime('%Y-%m-%d'),
        time_slot: '18:00',
        adults: 2,
        children: 0,
        reservation_period_id: reservation_period.id
      }

      post restaurant_reservations_path(restaurant.slug), params: params

      # 應該根據餐廳政策接受或拒絕，但不會崩潰
      expect([200, 302, 422]).to include(response.status)
    end

    it 'handles leap year dates' do
      # 如果今年是閏年，測試2月29日
      if Date.current.leap?
        leap_date = Date.new(Date.current.year, 2, 29)

        params = {
          reservation: {
            customer_name: '閏年客戶',
            customer_phone: '0912345678',
            customer_email: 'leap@example.com'
          },
          date: leap_date.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 2,
          children: 0,
          reservation_period_id: reservation_period.id
        }

        post restaurant_reservations_path(restaurant.slug), params: params
        expect([200, 302, 422]).to include(response.status)
      end
    end

    it 'handles timezone edge cases' do
      # 測試時區邊界時間
      midnight_params = {
        reservation: {
          customer_name: '午夜客戶',
          customer_phone: '0912345678',
          customer_email: 'midnight@example.com'
        },
        date: Date.tomorrow.strftime('%Y-%m-%d'),
        time_slot: '00:00',
        adults: 2,
        children: 0,
        reservation_period_id: reservation_period.id
      }

      post restaurant_reservations_path(restaurant.slug), params: midnight_params
      expect([200, 302, 422]).to include(response.status)
    end
  end

  describe 'Input validation edge cases' do
    it 'handles extremely long input strings' do
      long_string = 'a' * 1000

      params = {
        reservation: {
          customer_name: long_string,
          customer_phone: '0912345678',
          customer_email: 'long@example.com'
        },
        date: Date.tomorrow.strftime('%Y-%m-%d'),
        time_slot: '18:00',
        adults: 2,
        children: 0,
        reservation_period_id: reservation_period.id
      }

      post restaurant_reservations_path(restaurant.slug), params: params

      # 應該驗證失敗但不會崩潰
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'handles special characters in input' do
      special_chars = "🍕🍷<script>alert('test')</script>特殊字符测试"

      params = {
        reservation: {
          customer_name: special_chars,
          customer_phone: '0912345678',
          customer_email: 'special@example.com'
        },
        date: Date.tomorrow.strftime('%Y-%m-%d'),
        time_slot: '18:00',
        adults: 2,
        children: 0,
        reservation_period_id: reservation_period.id
      }

      post restaurant_reservations_path(restaurant.slug), params: params

      if response.status == 302 # 如果成功
        reservation = Reservation.last
        # 確保特殊字符被正確處理，沒有XSS
        expect(reservation.customer_name).not_to include('<script>')
      end
    end

    it 'handles malformed phone numbers' do
      malformed_phones = [
        '++886-912-345-678',
        '0912345678' * 10, # 太長
        '123',             # 太短
        'not-a-phone',     # 非數字
        '０９１２３４５６７８' # 全形數字
      ]

      malformed_phones.each do |phone|
        params = {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: phone,
            customer_email: 'test@example.com'
          },
          date: Date.tomorrow.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 2,
          children: 0,
          reservation_period_id: reservation_period.id
        }

        post restaurant_reservations_path(restaurant.slug), params: params

        # 應該驗證失敗或正規化處理
        if response.status == 302
          reservation = Reservation.last
          expect(reservation.customer_phone).to match(/\A[\d\-+\s()]+\z/)
        else
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end
  end

  describe 'Network and performance edge cases' do
    it 'handles slow database responses' do
      # Mock 慢速資料庫回應
      allow_any_instance_of(ActiveRecord::Relation).to receive(:find_by!).and_wrap_original do |method, *args|
        sleep 0.1 # 模擬延遲
        method.call(*args)
      end

      start_time = Time.current

      get new_restaurant_reservation_path(restaurant.slug), params: {
        date: Date.tomorrow.strftime('%Y-%m-%d'),
        adults: 2,
        children: 0,
        time: '18:00',
        period_id: reservation_period.id
      }

      end_time = Time.current
      response_time = end_time - start_time

      # 應該返回成功狀態或重定向，但不會崩潰
      expect([200, 302]).to include(response.status)
      expect(response_time).to be < 10.seconds # 合理的超時限制
    end

    it 'handles memory pressure scenarios' do
      # 模擬記憶體壓力（創建大量物件）
      large_objects = []
      100.times { large_objects << ('x' * 10_000) }

      params = {
        reservation: {
          customer_name: '記憶體測試',
          customer_phone: '0912345678',
          customer_email: 'memory@example.com'
        },
        date: Date.tomorrow.strftime('%Y-%m-%d'),
        time_slot: '18:00',
        adults: 2,
        children: 0,
        reservation_period_id: reservation_period.id
      }

      expect do
        post restaurant_reservations_path(restaurant.slug), params: params
      end.not_to raise_error

      # 清理
      large_objects.clear
      GC.start
    end
  end

  describe 'Cache consistency edge cases' do
    it 'handles cache invalidation during concurrent updates' do
      # 同時更新餐廳設定和建立訂位
      threads = []

      threads << Thread.new do
        restaurant.reservation_policy.update!(max_party_size: 10)
      end

      threads << Thread.new do
        params = {
          reservation: {
            customer_name: '快取測試',
            customer_phone: '0912345678',
            customer_email: 'cache@example.com'
          },
          date: Date.tomorrow.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 8,
          children: 0,
          reservation_period_id: reservation_period.id
        }

        post restaurant_reservations_path(restaurant.slug), params: params
      end

      threads.each(&:join)

      # 應該有一致的結果，不會有快取不一致的問題
      expect([200, 302, 422]).to include(response.status)
    end
  end
end
