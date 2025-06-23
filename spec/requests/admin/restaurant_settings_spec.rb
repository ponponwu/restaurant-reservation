require 'rails_helper'

RSpec.describe 'Admin::RestaurantSettings' do
  let(:user) { create(:user, :admin) }
  let(:restaurant) { create(:restaurant) }

  before do
    sign_in user
  end

  describe 'GET /admin/restaurant_settings/restaurants/:restaurant_slug' do
    it 'returns http success' do
      get admin_restaurant_settings_restaurant_index_path(restaurant.slug)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /admin/restaurant_settings/restaurants/:restaurant_slug/business_periods' do
    it 'returns http success' do
      get admin_restaurant_settings_restaurant_business_periods_path(restaurant.slug)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /admin/restaurant_settings/restaurants/:restaurant_slug/closure_dates' do
    it 'returns http success' do
      get admin_restaurant_settings_restaurant_closure_dates_path(restaurant.slug)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /admin/restaurant_settings/restaurants/:restaurant_slug/reservation_policies' do
    it 'returns http success' do
      get admin_restaurant_settings_restaurant_reservation_policies_path(restaurant.slug)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'authorization' do
    context 'when user is not admin or manager' do
      let(:regular_user) { create(:user) }

      before do
        sign_out user
        sign_in regular_user
      end

      it 'redirects to unauthorized page' do
        get admin_restaurant_settings_restaurant_index_path(restaurant.slug)
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when user is not signed in' do
      before { sign_out user }

      it 'redirects to sign in page' do
        get admin_restaurant_settings_restaurant_index_path(restaurant.slug)
        expect(response).to have_http_status(:redirect)
      end
    end
  end
end
