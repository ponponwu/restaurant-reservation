require 'rails_helper'

RSpec.describe 'Admin::BusinessPeriods' do
  let(:user) { create(:user, :admin) }
  let(:restaurant) { create(:restaurant) }
  let(:business_period) { create(:business_period, restaurant: restaurant) }

  before do
    sign_in user
  end

  describe 'GET /admin/restaurants/:restaurant_id/business_periods' do
    it 'returns http success' do
      get admin_restaurant_business_periods_path(restaurant)
      expect(response).to have_http_status(:success)
    end

    it 'displays business periods' do
      business_period
      get admin_restaurant_business_periods_path(restaurant)
      expect(response.body).to include(business_period.name)
    end
  end

  describe 'GET /admin/restaurants/:restaurant_id/business_periods/:id' do
    it 'returns http success' do
      get admin_restaurant_business_period_path(restaurant, business_period)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /admin/restaurants/:restaurant_id/business_periods/new' do
    it 'returns http success' do
      get new_admin_restaurant_business_period_path(restaurant)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /admin/restaurants/:restaurant_id/business_periods' do
    let(:valid_params) do
      {
        business_period: {
          name: 'lunch',
          display_name: '午餐時段',
          start_time: '11:30',
          end_time: '14:30',
          active: true,
          days_of_week: %w[monday tuesday wednesday thursday friday]
        }
      }
    end

    it 'creates a new business period' do
      expect do
        post admin_restaurant_business_periods_path(restaurant), params: valid_params
      end.to change(restaurant.business_periods, :count).by(1)
    end

    it 'redirects after successful creation' do
      post admin_restaurant_business_periods_path(restaurant), params: valid_params
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'GET /admin/restaurants/:restaurant_id/business_periods/:id/edit' do
    it 'returns http success' do
      get edit_admin_restaurant_business_period_path(restaurant, business_period)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'PATCH /admin/restaurants/:restaurant_id/business_periods/:id' do
    let(:update_params) do
      {
        business_period: {
          display_name: '更新後的名稱'
        }
      }
    end

    it 'updates the business period' do
      patch admin_restaurant_business_period_path(restaurant, business_period), params: update_params
      business_period.reload
      expect(business_period.display_name).to eq('更新後的名稱')
    end

    it 'redirects after successful update' do
      patch admin_restaurant_business_period_path(restaurant, business_period), params: update_params
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'DELETE /admin/restaurants/:restaurant_id/business_periods/:id' do
    it 'deletes the business period' do
      business_period
      expect do
        delete admin_restaurant_business_period_path(restaurant, business_period)
      end.to change(restaurant.business_periods, :count).by(-1)
    end

    it 'redirects after deletion' do
      delete admin_restaurant_business_period_path(restaurant, business_period)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'PATCH /admin/restaurants/:restaurant_id/business_periods/:id/toggle_active' do
    it 'toggles business period status' do
      original_active = business_period.active
      patch toggle_active_admin_restaurant_business_period_path(restaurant, business_period)
      business_period.reload
      expect(business_period.active).not_to eq(original_active)
    end

    it 'redirects after toggle' do
      patch toggle_active_admin_restaurant_business_period_path(restaurant, business_period)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'authorization' do
    context 'when user is not admin' do
      let(:other_restaurant) { create(:restaurant) }
      let(:regular_user) { create(:user, :manager, restaurant: other_restaurant) }

      before do
        sign_out user
        sign_in regular_user
      end

      it 'redirects to unauthorized page' do
        get admin_restaurant_business_periods_path(restaurant)
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(admin_restaurants_path)
      end
    end

    context 'when user has no restaurant' do
      let(:employee_without_restaurant) { create(:user, role: :employee) }

      before do
        sign_out user
        sign_in employee_without_restaurant
      end

      it 'redirects to unauthorized page' do
        get admin_restaurant_business_periods_path(restaurant)
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(admin_restaurants_path)
      end
    end

    context 'when user is not signed in' do
      before { sign_out user }

      it 'redirects to sign in page' do
        get admin_restaurant_business_periods_path(restaurant)
        expect(response).to have_http_status(:redirect)
      end
    end
  end
end
