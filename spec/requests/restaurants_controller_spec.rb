require 'rails_helper'

RSpec.describe RestaurantsController do
  let(:restaurant) { create(:restaurant) }
  let(:reservation_policy) { restaurant.reservation_policy || restaurant.create_reservation_policy! }

  describe 'API endpoint protection when reservation disabled' do
    before do
      reservation_policy.update!(reservation_enabled: false)
    end

    describe 'GET #available_days' do
      it 'returns service unavailable error' do
        get restaurant_available_days_path(restaurant.slug, format: :json)

        expect(response).to have_http_status(:service_unavailable)
        json_response = response.parsed_body
        expect(json_response['message']).to include('線上訂位')
        expect(json_response['reservation_enabled']).to be false
      end
    end

    describe 'GET #available_dates' do
      it 'returns service unavailable error' do
        get restaurant_available_dates_path(restaurant.slug, format: :json),
            params: { year: Date.current.year, month: Date.current.month }

        expect(response).to have_http_status(:service_unavailable)
        json_response = response.parsed_body
        expect(json_response['message']).to include('線上訂位')
        expect(json_response['reservation_enabled']).to be false
      end
    end

    describe 'GET #available_times' do
      it 'returns service unavailable error' do
        get restaurant_available_times_path(restaurant.slug, format: :json),
            params: {
              date: 1.day.from_now.strftime('%Y-%m-%d'),
              party_size: 4
            }

        expect(response).to have_http_status(:service_unavailable)
        json_response = response.parsed_body
        expect(json_response['message']).to include('線上訂位')
        expect(json_response['reservation_enabled']).to be false
      end
    end
  end

  describe 'API endpoints when reservation enabled' do
    before do
      reservation_policy.update!(reservation_enabled: true)
      # 創建必要的營業時間和桌位
      create(:business_period,
             restaurant: restaurant,
             days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
      create(:table, restaurant: restaurant)
    end

    describe 'GET #available_days' do
      it 'returns available days' do
        get restaurant_available_days_path(restaurant.slug, format: :json)

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response).to have_key('has_capacity')
        expect(json_response).to have_key('max_days')
      end
    end

    describe 'GET #available_dates' do
      it 'returns available dates' do
        get restaurant_available_dates_path(restaurant.slug, format: :json),
            params: { party_size: 4 }

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response).to have_key('available_dates')
      end
    end

    describe 'GET #available_times' do
      it 'returns available times' do
        get restaurant_available_times_path(restaurant.slug, format: :json),
            params: {
              date: 1.day.from_now.strftime('%Y-%m-%d'),
              party_size: 4
            }

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response).to have_key('available_times')
      end
    end
  end

  describe 'same-day booking restriction' do
    before do
      reservation_policy.update!(
        reservation_enabled: true,
        advance_booking_days: 30,
        minimum_advance_hours: 1
      )
      create(:business_period,
             restaurant: restaurant,
             days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
      create(:table, restaurant: restaurant)
    end

    describe 'available_dates endpoint' do
      it 'excludes current date from available dates' do
        get restaurant_available_dates_path(restaurant.slug, format: :json),
            params: { party_size: 4 }

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body

        # 驗證返回的日期不包含今天
        expect(json_response['available_dates']).not_to include(Date.current.to_s)

        # 驗證最早的日期是明天或之後
        if json_response['available_dates'].any?
          earliest_date = Date.parse(json_response['available_dates'].first)
          expect(earliest_date).to be > Date.current
        end
      end
    end

    describe 'available_times endpoint' do
      it 'rejects current date requests' do
        get restaurant_available_times_path(restaurant.slug, format: :json),
            params: {
              date: Date.current.strftime('%Y-%m-%d'),
              party_size: 4
            }

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['error']).to eq('不可預定當天或過去的日期')
      end

      it 'rejects past date requests' do
        past_date = Date.current - 1.day

        get restaurant_available_times_path(restaurant.slug, format: :json),
            params: {
              date: past_date.strftime('%Y-%m-%d'),
              party_size: 4
            }

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['error']).to eq('不可預定當天或過去的日期')
      end

      it 'allows future date requests' do
        future_date = Date.current + 1.day

        get restaurant_available_times_path(restaurant.slug, format: :json),
            params: {
              date: future_date.strftime('%Y-%m-%d'),
              party_size: 4
            }

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response).to have_key('available_times')
      end
    end
  end

  describe 'phone booking limit API integration' do
    let(:phone_number) { '0912345678' }

    before do
      reservation_policy.update!(
        reservation_enabled: true,
        max_bookings_per_phone: 2,
        phone_limit_period_days: 30
      )
      # 創建必要的營業時間和桌位
      create(:business_period,
             restaurant: restaurant,
             days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
      create(:table, restaurant: restaurant)
    end

    context 'when phone limit is reached' do
      before do
        # 創建2個現有訂位（達到限制）
        create_list(:reservation, 2,
                    restaurant: restaurant,
                    customer_phone: phone_number,
                    reservation_datetime: 5.days.from_now,
                    status: :confirmed)
      end

      it 'available_times returns limit exceeded warning' do
        get restaurant_available_times_path(restaurant.slug, format: :json),
            params: {
              date: 1.day.from_now.strftime('%Y-%m-%d'),
              party_size: 4,
              phone: phone_number
            }

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['phone_limit_exceeded']).to be true
        expect(json_response['phone_limit_message']).to include('訂位失敗')
      end
    end

    context 'when under phone limit' do
      before do
        # 創建1個現有訂位（未達限制）
        create(:reservation,
               restaurant: restaurant,
               customer_phone: phone_number,
               reservation_datetime: 5.days.from_now,
               status: :confirmed)
      end

      it 'available_times returns normal response' do
        get restaurant_available_times_path(restaurant.slug, format: :json),
            params: {
              date: 1.day.from_now.strftime('%Y-%m-%d'),
              party_size: 4,
              phone: phone_number
            }

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['phone_limit_exceeded']).to be false
        expect(json_response['remaining_bookings']).to eq(1)
      end
    end
  end

  describe 'party size limit API integration' do
    before do
      reservation_policy.update!(
        reservation_enabled: true,
        min_party_size: 2,
        max_party_size: 6
      )
      create(:business_period,
             restaurant: restaurant,
             days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
      create(:table, restaurant: restaurant, capacity: 8, max_capacity: 8)
    end

    context 'with invalid party size' do
      it 'returns error for party size too small' do
        get restaurant_available_times_path(restaurant.slug, format: :json),
            params: {
              date: 1.day.from_now.strftime('%Y-%m-%d'),
              party_size: 1
            }

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['error']).to include('人數超出限制')
      end

      it 'returns error for party size too large' do
        get restaurant_available_times_path(restaurant.slug, format: :json),
            params: {
              date: 1.day.from_now.strftime('%Y-%m-%d'),
              party_size: 10
            }

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['error']).to include('人數超出限制')
      end
    end

    context 'with valid party size' do
      it 'returns available times' do
        get restaurant_available_times_path(restaurant.slug, format: :json),
            params: {
              date: 1.day.from_now.strftime('%Y-%m-%d'),
              party_size: 4
            }

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response).to have_key('available_times')
      end
    end
  end

  describe 'booking advance limit API integration' do
    before do
      reservation_policy.update!(
        reservation_enabled: true,
        advance_booking_days: 7,
        minimum_advance_hours: 24
      )
      create(:business_period,
             restaurant: restaurant,
             days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
      create(:table, restaurant: restaurant)
    end

    context 'with date too far in advance' do
      it 'returns error' do
        far_date = (Date.current + 10.days).strftime('%Y-%m-%d')

        get restaurant_available_times_path(restaurant.slug, format: :json),
            params: {
              date: far_date,
              party_size: 4
            }

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['error']).to include('超出預約範圍')
      end
    end

    context 'with date too close' do
      it 'returns error for time too close to minimum advance hours' do
        close_date = (Date.current + 12.hours).strftime('%Y-%m-%d')

        get restaurant_available_times_path(restaurant.slug, format: :json),
            params: {
              date: close_date,
              party_size: 4
            }

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['error']).to include('不可預定當天')
      end
    end

    context 'with valid date range' do
      it 'returns available times' do
        valid_date = (Date.current + 3.days).strftime('%Y-%m-%d')

        get restaurant_available_times_path(restaurant.slug, format: :json),
            params: {
              date: valid_date,
              party_size: 4
            }

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response).to have_key('available_times')
      end
    end
  end

  describe 'error response format consistency' do
    before do
      reservation_policy.update!(reservation_enabled: false)
    end

    it 'returns consistent error format across all endpoints' do
      endpoints = [
        [:get, restaurant_available_days_path(restaurant.slug, format: :json)],
        [:get, restaurant_available_dates_path(restaurant.slug, format: :json), { year: 2024, month: 1 }],
        [:get, restaurant_available_times_path(restaurant.slug, format: :json), { date: Date.current.strftime('%Y-%m-%d'), party_size: 4 }]
      ]

      endpoints.each do |method, path, params|
        params ||= {}
        send(method, path, params: params)

        expect(response).to have_http_status(:service_unavailable)
        json_response = response.parsed_body
        expect(json_response).to have_key('message')
        expect(json_response).to have_key('reservation_enabled')
        expect(json_response['reservation_enabled']).to be false
      end
    end
  end
end
