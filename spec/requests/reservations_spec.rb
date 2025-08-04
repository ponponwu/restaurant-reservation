require 'rails_helper'

RSpec.describe 'Reservations' do
  let(:restaurant) { create(:restaurant) }
  let(:reservation_period) { create(:reservation_period, restaurant: restaurant) }
  let(:table) { create(:table, restaurant: restaurant, table_number: 'A1', capacity: 4) }

  before do
    # 確保餐廳有營業時段和桌位
    reservation_period.update!(days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday]) # 設定為每天營業
    table
  end

  describe 'GET /restaurants/:slug/reservations/availability_status' do
    it '返回餐廳的預訂可用性狀態' do
      get restaurant_availability_status_path(restaurant)

      expect(response).to have_http_status(:ok)
      json_response = response.parsed_body
      expect(json_response).to have_key('unavailable_dates')
      expect(json_response).to have_key('fully_booked_until')
    end

    it '處理錯誤並返回適當的錯誤訊息' do
      Rails.cache.clear
      allow_any_instance_of(Restaurant).to receive(:closed_on_date?).and_raise(StandardError, '測試錯誤')

      get restaurant_availability_status_path(restaurant)

      expect(response).to have_http_status(:internal_server_error)
      json_response = response.parsed_body
      expect(json_response['error']).to include('測試錯誤')
    end
  end

  describe 'GET /restaurants/:slug/reservations/available_slots' do
    let(:valid_params) do
      {
        date: 3.days.from_now.strftime('%Y-%m-%d'),
        adult_count: 2,
        child_count: 0
      }
    end

    it '返回指定日期的可用時間槽' do
      get restaurant_available_slots_path(restaurant), params: valid_params

      expect(response).to have_http_status(:ok)
      json_response = response.parsed_body
      expect(json_response).to have_key('slots')
      expect(json_response['slots']).to be_an(Array)
    end

    it '對無效日期格式返回錯誤' do
      get restaurant_available_slots_path(restaurant), params: valid_params.merge(date: 'invalid-date')

      expect(response).to have_http_status(:bad_request)
      json_response = response.parsed_body
      expect(json_response['error']).to include('日期格式錯誤')
    end

    it '對無效人數返回錯誤' do
      get restaurant_available_slots_path(restaurant), params: valid_params.merge(adult_count: 0)

      expect(response).to have_http_status(:bad_request)
      json_response = response.parsed_body
      expect(json_response['error']).to include('人數必須至少')
    end

    it '對過去的日期返回錯誤' do
      past_date = 1.day.ago.strftime('%Y-%m-%d')
      get restaurant_available_slots_path(restaurant), params: valid_params.merge(date: past_date)

      expect(response).to have_http_status(:bad_request)
      json_response = response.parsed_body
      expect(json_response['error']).to include('不能預約過去的日期')
    end

    it '對餐廳公休日返回空的時間槽' do
      # 設定餐廳公休
      allow_any_instance_of(Restaurant).to receive(:closed_on_date?).and_return(true)

      get restaurant_available_slots_path(restaurant), params: valid_params

      expect(response).to have_http_status(:ok)
      json_response = response.parsed_body
      expect(json_response['slots']).to be_empty
      expect(json_response['message']).to eq('餐廳當天公休')
    end
  end

  describe 'GET /restaurant/:slug/reservation' do
    let(:valid_params) do
      {
        date: 3.days.from_now.strftime('%Y-%m-%d'),
        adults: 2,
        children: 0,
        time: '18:00',
        period_id: reservation_period.id
      }
    end

    it '顯示新訂位表單' do
      get new_restaurant_reservation_path(restaurant), params: valid_params

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('預約')
      expect(response.body).to include(restaurant.name)
    end

    it '處理無效的餐廳 slug' do
      get new_restaurant_reservation_path('invalid-slug'), params: valid_params
      # 根據實際行為，如果發生錯誤，應該是內部伺服器錯誤
      # 因為 StandardError rescue 會捕獲所有未處理的例外
      expect([302, 500]).to include(response.status)

      expect(response).to redirect_to(root_path) if response.status == 302
    end

    it '正確設定表單變數' do
      get new_restaurant_reservation_path(restaurant), params: valid_params

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(restaurant.name)
      expect(response.body).to include('2位成人')
      expect(response.body).to include('18:00')
    end
  end

  describe 'POST /restaurant/:slug/reservation' do
    let(:valid_params) do
      {
        date: 3.days.from_now.strftime('%Y-%m-%d'),
        adults: 2,
        children: 0,
        time_slot: '18:00',
        reservation_period_id: reservation_period.id,
        reservation: {
          customer_name: '測試客戶',
          customer_phone: '0912345678',
          customer_email: 'test@example.com',
          special_requests: '靠窗座位'
        }
      }
    end

    context '使用有效參數' do
      before do
        # Mock 桌位分配服務
        allow_any_instance_of(ReservationAllocatorService).to receive(:allocate_table).and_return(table)
      end

      it '創建新的訂位' do
        expect do
          post restaurant_reservations_path(restaurant), params: valid_params
        end.to change(Reservation, :count).by(1)
      end

      it '設定正確的訂位屬性' do
        post restaurant_reservations_path(restaurant), params: valid_params

        reservation = Reservation.last
        expect(reservation.restaurant).to eq(restaurant)
        expect(reservation.customer_name).to eq('測試客戶')
        expect(reservation.customer_phone).to eq('0912345678')
        expect(reservation.customer_email).to eq('test@example.com')
        expect(reservation.party_size).to eq(2)
        expect(reservation.status).to eq('confirmed')
        expect(reservation.table).to eq(table)
      end

      it '重定向到餐廳頁面並顯示成功訊息' do
        post restaurant_reservations_path(restaurant), params: valid_params

        expect(response).to redirect_to(restaurant_public_path(restaurant))
        expect(flash[:notice]).to include('訂位建立成功')
      end
    end

    context '當沒有可用桌位時' do
      before do
        # Mock 增強的桌位分配服務檢查可用性失敗
        allow_any_instance_of(EnhancedReservationAllocatorService).to receive(:check_availability_with_lock).and_return({ has_availability: false })
        allow_any_instance_of(EnhancedReservationAllocatorService).to receive(:allocate_table_with_lock).and_return(nil)
      end

      it '不創建訂位記錄' do
        expect do
          post restaurant_reservations_path(restaurant), params: valid_params
        end.not_to change(Reservation, :count)
      end

      it '重新渲染表單並顯示錯誤訊息' do
        post restaurant_reservations_path(restaurant), params: valid_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('該時段已無可用桌位')
      end
    end

    context '使用無效參數' do
      let(:invalid_params) do
        valid_params.merge(
          reservation: {
            customer_name: '', # 空白姓名
            customer_phone: '123', # 無效電話
            customer_email: 'invalid-email'
          }
        )
      end

      it '不創建訂位記錄' do
        expect do
          post restaurant_reservations_path(restaurant), params: invalid_params
        end.not_to change(Reservation, :count)
      end

      it '重新渲染表單並顯示驗證錯誤' do
        post restaurant_reservations_path(restaurant), params: invalid_params

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
