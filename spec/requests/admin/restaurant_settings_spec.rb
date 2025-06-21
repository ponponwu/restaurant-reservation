require 'rails_helper'

RSpec.describe 'Admin::RestaurantSettings' do
  describe 'GET /index' do
    it 'returns http success' do
      get '/admin/restaurant_settings/index'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /business_periods' do
    it 'returns http success' do
      get '/admin/restaurant_settings/business_periods'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /closure_dates' do
    it 'returns http success' do
      get '/admin/restaurant_settings/closure_dates'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /reservation_policies' do
    it 'returns http success' do
      get '/admin/restaurant_settings/reservation_policies'
      expect(response).to have_http_status(:success)
    end
  end
end
