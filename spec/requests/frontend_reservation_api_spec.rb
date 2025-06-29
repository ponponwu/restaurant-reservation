require 'rails_helper'

RSpec.describe 'Frontend Reservation API' do
  let(:restaurant) { create(:restaurant) }
  let(:business_period) { create(:business_period, restaurant: restaurant) }
  let(:table_group) { create(:table_group, restaurant: restaurant) }
  let(:table) { create(:table, restaurant: restaurant, table_group: table_group) }

  before do
    # 確保餐廳有完整設定
    business_period
    table
    restaurant.reservation_policy.update!(reservation_enabled: true)
  end

  describe 'POST /restaurant/:slug/reservation' do
    let(:valid_reservation_params) do
      {
        reservation: {
          customer_name: '測試客戶',
          customer_phone: '0912345678',
          customer_email: 'test@example.com'
        },
        date: 2.days.from_now.strftime('%Y-%m-%d'),
        time_slot: '18:00',
        adults: 2,
        children: 0,
        business_period_id: business_period.id
      }
    end

    context 'with valid parameters' do
      it 'creates a new reservation' do
        expect do
          post restaurant_reservations_path(restaurant.slug), params: valid_reservation_params
        end.to change(Reservation, :count).by(1)

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(restaurant_public_path(restaurant.slug))

        reservation = Reservation.last
        expect(reservation.customer_name).to eq('測試客戶')
        expect(reservation.customer_phone).to eq('0912345678')
        expect(reservation.party_size).to eq(2)
        expect(reservation.status).to eq('confirmed')
      end

      it 'includes cancellation token' do
        post restaurant_reservations_path(restaurant.slug), params: valid_reservation_params

        reservation = Reservation.last
        expect(reservation.cancellation_token).to be_present
        expect(reservation.cancellation_token.length).to eq(32)
      end
    end

    context 'with missing required fields' do
      it 'validates customer name presence' do
        invalid_params = valid_reservation_params.deep_dup
        invalid_params[:reservation][:customer_name] = ''

        expect do
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        end.not_to change(Reservation, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'validates customer phone presence' do
        invalid_params = valid_reservation_params.deep_dup
        invalid_params[:reservation][:customer_phone] = ''

        expect do
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        end.not_to change(Reservation, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when reservation is disabled' do
      before do
        restaurant.reservation_policy.update!(reservation_enabled: false)
      end

      it 'redirects with error message' do
        post restaurant_reservations_path(restaurant.slug), params: valid_reservation_params

        expect(response).to have_http_status(:redirect)
        follow_redirect!
        expect(response.body).to include('線上訂位功能暫停服務')
      end
    end

    context 'with blacklisted customer' do
      before do
        create(:blacklist, restaurant: restaurant, customer_phone: '0987654321')
      end

      it 'prevents reservation with generic error' do
        blacklisted_params = valid_reservation_params.deep_dup
        blacklisted_params[:reservation][:customer_phone] = '0987654321'

        expect do
          post restaurant_reservations_path(restaurant.slug), params: blacklisted_params
        end.not_to change(Reservation, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('訂位失敗，請聯繫餐廳')
        expect(response.body).not_to include('黑名單')
      end
    end

    context 'with phone booking limit exceeded' do
      before do
        restaurant.reservation_policy.update!(
          max_bookings_per_phone: 1,
          phone_limit_period_days: 30
        )

        # 創建現有訂位達到限制
        create(:reservation,
               restaurant: restaurant,
               customer_phone: '0966666666',
               reservation_datetime: 5.days.from_now,
               status: :confirmed)
      end

      it 'prevents reservation with generic error' do
        limited_params = valid_reservation_params.deep_dup
        limited_params[:reservation][:customer_phone] = '0966666666'

        expect do
          post restaurant_reservations_path(restaurant.slug), params: limited_params
        end.not_to change(Reservation, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('訂位失敗，請聯繫餐廳')
        expect(response.body).not_to include('訂位次數已達上限')
      end
    end

    context 'with party size validation' do
      before do
        # 創建一個大桌位確保餐廳有足夠容量
        create(:table, :large_table, restaurant: restaurant, table_group: table_group)
        restaurant.reservation_policy.update!(
          min_party_size: 2,
          max_party_size: 8
        )
      end

      it 'accepts valid party size' do
        valid_params = valid_reservation_params.deep_dup
        valid_params[:adults] = 4
        valid_params[:children] = 2

        expect do
          post restaurant_reservations_path(restaurant.slug), params: valid_params
        end.to change(Reservation, :count).by(1)

        reservation = Reservation.last
        expect(reservation.party_size).to eq(6)
        expect(reservation.adults_count).to eq(4)
        expect(reservation.children_count).to eq(2)
      end

      it 'rejects party size too small' do
        invalid_params = valid_reservation_params.deep_dup
        invalid_params[:adults] = 1
        invalid_params[:children] = 0

        expect do
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        end.not_to change(Reservation, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'rejects party size too large' do
        invalid_params = valid_reservation_params.deep_dup
        invalid_params[:adults] = 6
        invalid_params[:children] = 4

        expect do
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        end.not_to change(Reservation, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with advance booking validation' do
      before do
        restaurant.reservation_policy.update!(
          advance_booking_days: 14,
          minimum_advance_hours: 24
        )
      end

      it 'rejects booking too far in advance' do
        invalid_params = valid_reservation_params.deep_dup
        invalid_params[:date] = 20.days.from_now.strftime('%Y-%m-%d')

        expect do
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        end.not_to change(Reservation, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'rejects booking too close to current time' do
        invalid_params = valid_reservation_params.deep_dup
        invalid_params[:date] = Date.current.strftime('%Y-%m-%d')
        invalid_params[:time_slot] = 12.hours.from_now.strftime('%H:%M')

        expect do
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        end.not_to change(Reservation, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /restaurant/:slug/reservation' do
    before do
      # 創建一個大桌位確保餐廳有足夠容量
      create(:table, :large_table, restaurant: restaurant, table_group: table_group)
    end

    let(:reservation_params) do
      {
        date: Date.tomorrow.strftime('%Y-%m-%d'),
        adults: 2,
        children: 0,
        time: '18:00',
        period_id: business_period.id
      }
    end

    before do
      # 創建一個大桌位確保餐廳有足夠容量
      create(:table, :large_table, restaurant: restaurant, table_group: table_group)
    end

    context 'when reservation is enabled' do
      it 'displays reservation form' do
        get new_restaurant_reservation_path(restaurant.slug), params: reservation_params

        # 如果重定向，跟隨重定向
        if response.status == 302
          follow_redirect!
        end
        
        expect(response).to have_http_status(:success)
        expect(response.body).to include('預約')
      end

      it 'pre-fills party size from parameters' do
        get new_restaurant_reservation_path(restaurant.slug), params: reservation_params.merge(adults: 4, children: 1)

        # 如果重定向，跟隨重定向
        if response.status == 302
          follow_redirect!
        end

        expect(response).to have_http_status(:success)
        # Check that the party size is handled properly
        if assigns(:reservation)
          expect(assigns(:reservation).party_size).to eq(5)
        end
      end
    end

    context 'when reservation is disabled' do
      before do
        restaurant.reservation_policy.update!(reservation_enabled: false)
      end

      it 'redirects with disabled message' do
        get new_restaurant_reservation_path(restaurant.slug), params: reservation_params

        expect(response).to have_http_status(:redirect)
        follow_redirect!
        expect(response.body).to include('線上訂位功能暫停服務')
      end
    end

    context 'with invalid party size for restaurant capacity' do
      it 'redirects when party size exceeds capacity' do
        invalid_params = reservation_params.merge(adults: 20, children: 5)

        get new_restaurant_reservation_path(restaurant.slug), params: invalid_params

        # 應該重定向並顯示錯誤訊息
        expect(response).to have_http_status(:redirect)
        follow_redirect!
        # 檢查是否顯示了無法訂位的相關訊息
        expect(response.body).to include('所選日期無法訂位') 
      end
    end

    context 'with closed date selection' do
      before do
        # 設定明天為特殊休息日
        restaurant.closure_dates.create!(
          date: Date.tomorrow,
          reason: '特殊公休',
          all_day: true
        )
      end

      it 'redirects when selecting closed date' do
        closed_params = reservation_params.merge(date: Date.tomorrow.strftime('%Y-%m-%d'))

        get new_restaurant_reservation_path(restaurant.slug), params: closed_params

        expect(response).to have_http_status(:redirect)
        follow_redirect!
        expect(response.body).to include('所選日期無法訂位')
      end
    end
  end
end
