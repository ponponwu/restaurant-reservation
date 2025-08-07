require 'rails_helper'

RSpec.describe 'Admin::RestaurantSettings' do
  let(:user) { create(:user, :super_admin) }
  let(:restaurant) { create(:restaurant) }

  before do
    post user_session_path, params: { user: { email: user.email, password: 'password123' } }
    follow_redirect!
  end

  describe 'GET /admin/restaurant_settings/restaurants/:restaurant_slug' do
    it 'returns http success' do
      get admin_restaurant_settings_restaurant_index_path(restaurant.slug)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /admin/restaurant_settings/restaurants/:restaurant_slug/reservation_periods' do
    it 'returns http success' do
      get admin_restaurant_settings_restaurant_reservation_periods_path(restaurant.slug)
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

  describe 'GET /admin/restaurant_settings/restaurants/:restaurant_slug/weekly_day/:weekday/edit' do
    it 'returns http success' do
      get admin_restaurant_settings_restaurant_edit_weekly_day_path(restaurant.slug, 1)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'PATCH /admin/restaurant_settings/restaurants/:restaurant_slug/weekly_day/:weekday' do
    it 'updates weekly reservation periods' do
      patch admin_restaurant_settings_restaurant_update_weekly_day_path(restaurant.slug, 1), params: {
        operation_mode: 'custom_hours',
        periods: [
          { start_time: '12:00', end_time: '14:00', interval: 30 },
          { start_time: '18:00', end_time: '20:00', interval: 30 }
        ]
      }
      expect(response).to have_http_status(:redirect)
      expect(restaurant.reservation_periods.for_weekday(1).count).to eq(2)
    end
  end

  describe 'authorization' do
    context 'when user is not admin or manager' do
      let(:regular_user) { create(:user) }

      before do
        delete destroy_user_session_path
        post user_session_path, params: { user: { email: regular_user.email, password: 'password123' } }
        follow_redirect!
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
