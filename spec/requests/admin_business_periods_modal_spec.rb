require 'rails_helper'

RSpec.describe 'Admin Business Periods Modal Fix', type: :request do
  let(:restaurant) { create(:restaurant) }
  let(:user) { create(:user, :manager, restaurant: restaurant) }
  let(:business_period) { create(:business_period, restaurant: restaurant) }

  before do
    sign_in user
  end

  describe 'Modal functionality' do
    it 'returns edit modal content successfully' do
      get edit_admin_restaurant_business_period_path(restaurant, business_period)
      
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<turbo-frame id="modal">')
      expect(response.body).to include('編輯營業時段')
    end
  end

  describe 'Toggle active functionality' do
    it 'toggles business period active status via PATCH' do
      expect(business_period).to be_active
      
      patch toggle_active_admin_restaurant_business_period_path(restaurant, business_period),
            headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
      
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('text/vnd.turbo-stream.html')
      expect(business_period.reload).not_to be_active
    end

    it 'handles restaurant settings page requests' do
      # Simulate request from restaurant settings page
      patch toggle_active_admin_restaurant_business_period_path(restaurant, business_period),
            headers: { 
              'Accept' => 'text/vnd.turbo-stream.html',
              'Referer' => admin_restaurant_settings_restaurant_business_periods_path(restaurant)
            }
      
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('text/vnd.turbo-stream.html')
      expect(business_period.reload).not_to be_active
    end
  end
end