require 'rails_helper'

RSpec.describe 'Restaurant Availability API', type: :request do
  let(:restaurant) { create(:restaurant, :with_reservation_periods, :with_tables) }
  let(:party_size) { 4 }

  before do
    # 確保餐廳有基本設定
    restaurant.reservation_policy || restaurant.create_reservation_policy
  end

  describe 'GET /restaurants/:slug/available_days' do
    it 'returns available days information' do
      get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: party_size }

      expect(response).to have_http_status(:success)

      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('weekly_closures')
      expect(json_response).to have_key('special_closures')
      expect(json_response).to have_key('max_days')
      expect(json_response).to have_key('has_capacity')
    end

    it 'includes weekly closure information' do
      get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: party_size }

      json_response = JSON.parse(response.body)
      expect(json_response['weekly_closures']).to be_an(Array)
      expect(json_response['max_days']).to be_a(Integer)
    end

    it 'checks restaurant capacity for party size' do
      # 模擬餐廳沒有足夠容量
      allow_any_instance_of(Restaurant)
        .to receive(:has_capacity_for_party_size?)
        .with(party_size)
        .and_return(false)

      get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: party_size }

      json_response = JSON.parse(response.body)
      expect(json_response['has_capacity']).to be false
    end

    it 'defaults party_size to 2 when not provided or invalid' do
      get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 0 }

      expect(response).to have_http_status(:success)
      # 應該使用預設值 2 而不是拒絕請求
    end
  end

  describe 'GET /restaurants/:slug/available_dates' do
    it 'returns available dates with business periods' do
      get "/restaurants/#{restaurant.slug}/available_dates", params: { party_size: party_size }

      expect(response).to have_http_status(:success)

      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('available_dates')
      expect(json_response).to have_key('has_capacity')
      expect(json_response).to have_key('reservation_periods')
      expect(json_response['available_dates']).to be_an(Array)
      expect(json_response['reservation_periods']).to be_an(Array)
    end

    it 'includes full_booked_until when no dates available but has capacity' do
      # 模擬有容量但沒有可用日期的情況
      allow_any_instance_of(Restaurant)
        .to receive(:has_capacity_for_party_size?)
        .and_return(true)

      allow_any_instance_of(RestaurantAvailabilityService)
        .to receive(:get_available_dates)
        .and_return([])

      get "/restaurants/#{restaurant.slug}/available_dates", params: { party_size: party_size }

      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('full_booked_until')
      expect(json_response['full_booked_until']).not_to be_nil
    end

    it 'does not include full_booked_until when restaurant has no capacity' do
      # 模擬餐廳沒有足夠容量的情況
      allow_any_instance_of(Restaurant)
        .to receive(:has_capacity_for_party_size?)
        .and_return(false)

      get "/restaurants/#{restaurant.slug}/available_dates", params: { party_size: party_size }

      json_response = JSON.parse(response.body)
      expect(json_response['full_booked_until']).to be_nil
      expect(json_response['has_capacity']).to be false
    end

    it 'validates party size range' do
      get "/restaurants/#{restaurant.slug}/available_dates", params: { party_size: 15 }

      expect(response).to have_http_status(:bad_request)

      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('人數必須在 1-12 人之間')
    end

    it 'handles adults and children parameters' do
      get "/restaurants/#{restaurant.slug}/available_dates",
          params: { party_size: party_size, adults: 3, children: 1 }

      expect(response).to have_http_status(:success)
    end

    it 'uses party_size as adults when adults not provided' do
      expect_any_instance_of(RestaurantAvailabilityService)
        .to receive(:get_available_dates)
        .with(party_size, party_size, 0)
        .and_return([])

      get "/restaurants/#{restaurant.slug}/available_dates",
          params: { party_size: party_size }
    end

    it 'handles server errors gracefully' do
      allow_any_instance_of(RestaurantAvailabilityService)
        .to receive(:get_available_dates)
        .and_raise(StandardError.new('Test error'))

      get "/restaurants/#{restaurant.slug}/available_dates", params: { party_size: party_size }

      expect(response).to have_http_status(:internal_server_error)

      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('伺服器錯誤')
    end
  end

  describe 'GET /restaurants/:slug/available_times' do
    let(:future_date) { 1.week.from_now.strftime('%Y-%m-%d') }

    it 'returns available times for a valid date' do
      get "/restaurants/#{restaurant.slug}/available_times",
          params: { date: future_date, party_size: party_size }

      expect(response).to have_http_status(:success)

      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('available_times')
      expect(json_response['available_times']).to be_an(Array)
    end

    it 'validates date format' do
      get "/restaurants/#{restaurant.slug}/available_times",
          params: { date: 'invalid-date', party_size: party_size }

      expect(response).to have_http_status(:bad_request)

      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('日期格式錯誤')
    end

    it 'rejects past dates' do
      past_date = 1.day.ago.strftime('%Y-%m-%d')

      get "/restaurants/#{restaurant.slug}/available_times",
          params: { date: past_date, party_size: party_size }

      expect(response).to have_http_status(:unprocessable_entity)

      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('不可預定當天或過去的日期')
    end

    it 'rejects today\'s date' do
      today = Date.current.strftime('%Y-%m-%d')

      get "/restaurants/#{restaurant.slug}/available_times",
          params: { date: today, party_size: party_size }

      expect(response).to have_http_status(:unprocessable_entity)

      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('不可預定當天或過去的日期')
    end

    it 'validates party size against restaurant policy' do
      # 設定餐廳政策限制
      restaurant.reservation_policy.update!(min_party_size: 2, max_party_size: 8)

      get "/restaurants/#{restaurant.slug}/available_times",
          params: { date: future_date, party_size: 10 }

      expect(response).to have_http_status(:unprocessable_entity)

      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('人數超出限制')
    end

    it 'checks advance booking days limit' do
      # 設定只能預約7天內
      restaurant.reservation_policy.update!(advance_booking_days: 7)
      far_future_date = 10.days.from_now.strftime('%Y-%m-%d')

      get "/restaurants/#{restaurant.slug}/available_times",
          params: { date: far_future_date, party_size: party_size }

      expect(response).to have_http_status(:unprocessable_entity)

      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('超出預約範圍')
    end

    it 'handles restaurant closure dates' do
      # 模擬餐廳當天公休
      allow_any_instance_of(Restaurant)
        .to receive(:closed_on_date?)
        .and_return(true)

      get "/restaurants/#{restaurant.slug}/available_times",
          params: { date: future_date, party_size: party_size }

      expect(response).to have_http_status(:success)

      json_response = JSON.parse(response.body)
      expect(json_response['available_times']).to be_empty
      expect(json_response['message']).to eq('餐廳當天公休')
    end

    it 'checks phone booking limits when phone provided' do
      phone_number = '0912345678'

      # 模擬電話預約限制
      allow_any_instance_of(ReservationPolicy)
        .to receive(:phone_booking_limit_exceeded?)
        .with(phone_number)
        .and_return(true)

      get "/restaurants/#{restaurant.slug}/available_times",
          params: { date: future_date, party_size: party_size, phone: phone_number }

      expect(response).to have_http_status(:success)

      json_response = JSON.parse(response.body)
      expect(json_response['phone_limit_exceeded']).to be true
      expect(json_response['phone_limit_message']).to eq('訂位失敗，請聯繫餐廳')
    end

    it 'sorts available times correctly' do
      get "/restaurants/#{restaurant.slug}/available_times",
          params: { date: future_date, party_size: party_size }

      json_response = JSON.parse(response.body)
      times = json_response['available_times']

      if times.length > 1
        time_strings = times.map { |t| t['time'] }
        expect(time_strings).to eq(time_strings.sort)
      end
    end

    it 'includes required time slot information' do
      get "/restaurants/#{restaurant.slug}/available_times",
          params: { date: future_date, party_size: party_size }

      json_response = JSON.parse(response.body)
      times = json_response['available_times']

      times.each do |time_slot|
        expect(time_slot).to have_key('time')
        expect(time_slot).to have_key('datetime')
        expect(time_slot).to have_key('reservation_period_id')
      end
    end

    it 'handles server errors gracefully' do
      allow_any_instance_of(RestaurantAvailabilityService)
        .to receive(:get_available_times)
        .and_raise(StandardError.new('Test error'))

      get "/restaurants/#{restaurant.slug}/available_times",
          params: { date: future_date, party_size: party_size }

      expect(response).to have_http_status(:internal_server_error)

      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('伺服器錯誤')
    end
  end

  describe 'restaurant not found' do
    it 'redirects when restaurant slug not found' do
      get '/restaurants/non-existent-restaurant/available_dates',
          params: { party_size: party_size }

      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'reservation disabled' do
    before do
      restaurant.reservation_policy.update!(reservation_enabled: false)
    end

    it 'returns service unavailable when reservations disabled' do
      get "/restaurants/#{restaurant.slug}/available_dates",
          params: { party_size: party_size }

      expect(response).to have_http_status(:service_unavailable)

      json_response = JSON.parse(response.body)
      expect(json_response['reservation_enabled']).to be false
      expect(json_response['message']).to include('暫停接受線上訂位')
    end
  end
end
