require 'rails_helper'

RSpec.describe 'Admin Reservation Periods Modal Fix', type: :request do
  let(:restaurant) { create(:restaurant) }
  let(:user) { create(:user, :manager, restaurant: restaurant) }
  let(:reservation_period) { create(:reservation_period, restaurant: restaurant) }

  before do
    post user_session_path, params: { user: { email: user.email, password: 'password123' } }
    follow_redirect!
  end

  describe 'Modal functionality' do
    it 'returns edit modal content successfully' do
      get edit_admin_restaurant_reservation_period_path(restaurant, reservation_period)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<turbo-frame id="modal">')
      expect(response.body).to include('編輯營業時段')
    end
  end

  describe 'Toggle active functionality' do
    it 'toggles reservation period active status via PATCH' do
      expect(reservation_period).to be_active

      patch toggle_active_admin_restaurant_reservation_period_path(restaurant, reservation_period),
            headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('text/vnd.turbo-stream.html')
      expect(reservation_period.reload).not_to be_active
    end

    it 'handles restaurant settings page requests' do
      # Simulate request from restaurant settings page
      patch toggle_active_admin_restaurant_reservation_period_path(restaurant, reservation_period),
            headers: {
              'Accept' => 'text/vnd.turbo-stream.html',
              'Referer' => admin_restaurant_settings_restaurant_reservation_periods_path(restaurant)
            }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('text/vnd.turbo-stream.html')
      expect(reservation_period.reload).not_to be_active
    end
  end
end
