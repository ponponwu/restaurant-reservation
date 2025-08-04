# 樂觀鎖併發控制測試
require 'rails_helper'

RSpec.describe ReservationsController, type: :controller do
  let!(:restaurant) { create(:restaurant) }
  let!(:table) { create(:restaurant_table, restaurant: restaurant, capacity: 4) }
  let!(:reservation_period) { create(:reservation_period, restaurant: restaurant) }

  before do
    # 設定基本參數
    @basic_params = {
      slug: restaurant.slug,
      reservation: {
        customer_name: '測試客戶',
        customer_phone: '0912345678',
        customer_email: 'test@example.com',
        party_size: 2,
        special_requests: ''
      },
      adults: 2,
      children: 0,
      time_slot: '18:00',
      date: Date.current.to_s,
      reservation_period_id: reservation_period.id
    }
  end

  describe '樂觀鎖併發測試' do
    it '樂觀鎖重試機制正常運作' do
      # 模擬樂觀鎖衝突
      allow_any_instance_of(Reservation).to receive(:save!).and_raise(ActiveRecord::StaleObjectError.new(nil, 'test'))

      post :create, params: @basic_params

      # 應該返回重試用盡的錯誤
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '資料庫約束防止重複預訂' do
      # 先建立一個成功的預訂
      post :create, params: @basic_params
      expect(response).to have_http_status(:found) # 重導向表示成功

      # 嘗試建立相同時段的預訂（不同手機號碼）
      duplicate_params = @basic_params.dup
      duplicate_params[:reservation][:customer_phone] = '0987654321'
      duplicate_params[:reservation][:customer_name] = '另一個客戶'

      post :create, params: duplicate_params

      # 應該失敗，因為桌位已被佔用
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '手機號碼重複預訂防護機制' do
      # 先建立一個成功的預訂
      post :create, params: @basic_params
      expect(response).to have_http_status(:found)

      # 嘗試用相同手機號碼在相同時段預訂
      post :create, params: @basic_params

      # 應該失敗
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe '效能測試' do
    it '無鎖定機制響應時間測試' do
      start_time = Time.current

      post :create, params: @basic_params

      end_time = Time.current
      response_time = end_time - start_time

      # 響應時間應該在 2 秒以內（樂觀鎖機制）
      expect(response_time).to be < 2.0
      puts "樂觀鎖機制響應時間: #{response_time.round(3)} 秒"
    end
  end
end
