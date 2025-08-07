require 'rails_helper'

RSpec.describe 'Admin::Blacklists' do
  let(:restaurant) { create(:restaurant) }
  let(:admin_user) { create(:user, :admin, restaurant: restaurant) }
  let(:blacklist) { create(:blacklist, restaurant: restaurant) }

  before do
    post user_session_path, params: { user: { email: admin_user.email, password: 'password123' } }
    follow_redirect!
  end

  describe 'GET /admin/restaurants/:restaurant_id/blacklists' do
    it 'returns http success' do
      get admin_restaurant_blacklists_path(restaurant)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /admin/restaurants/:restaurant_id/blacklists/:id' do
    it 'returns http success' do
      get admin_restaurant_blacklist_path(restaurant, blacklist)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /admin/restaurants/:restaurant_id/blacklists/new' do
    it 'returns http success' do
      get new_admin_restaurant_blacklist_path(restaurant)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /admin/restaurants/:restaurant_id/blacklists' do
    it 'creates a new blacklist entry' do
      blacklist_params = {
        customer_phone: '0912345678',
        customer_name: 'Test Blacklist',
        reason: 'Test reason',
        status: 'active'
      }

      expect do
        post admin_restaurant_blacklists_path(restaurant), params: { blacklist: blacklist_params }
      end.to change(restaurant.blacklists, :count).by(1)

      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'GET /admin/restaurants/:restaurant_id/blacklists/:id/edit' do
    it 'returns http success' do
      get edit_admin_restaurant_blacklist_path(restaurant, blacklist)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'PATCH /admin/restaurants/:restaurant_id/blacklists/:id' do
    it 'updates the blacklist entry' do
      updated_params = { reason: 'Updated reason' }

      patch admin_restaurant_blacklist_path(restaurant, blacklist), params: { blacklist: updated_params }
      expect(response).to have_http_status(:redirect)

      blacklist.reload
      expect(blacklist.reason).to eq('Updated reason')
    end
  end

  describe 'DELETE /admin/restaurants/:restaurant_id/blacklists/:id' do
    it 'destroys the blacklist entry' do
      blacklist # 確保 blacklist 存在

      expect do
        delete admin_restaurant_blacklist_path(restaurant, blacklist)
      end.to change(restaurant.blacklists, :count).by(-1)

      expect(response).to have_http_status(:redirect)
    end
  end
end
