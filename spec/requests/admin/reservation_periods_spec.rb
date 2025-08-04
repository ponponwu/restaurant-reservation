require 'rails_helper'

RSpec.describe 'Admin::ReservationPeriods' do
  let(:user) { create(:user, :super_admin) }
  let(:restaurant) { create(:restaurant) }
  let(:reservation_period) { create(:reservation_period, restaurant: restaurant) }

  before do
    sign_in user
  end

  describe 'GET /admin/restaurants/:restaurant_id/reservation_periods' do
    it 'returns http success' do
      get admin_restaurant_reservation_periods_path(restaurant)
      expect(response).to have_http_status(:success)
    end

    it 'displays reservation periods' do
      reservation_period
      get admin_restaurant_reservation_periods_path(restaurant)
      expect(response.body).to include(reservation_period.name)
    end
  end

  describe 'GET /admin/restaurants/:restaurant_id/reservation_periods/:id' do
    it 'returns http success' do
      get admin_restaurant_reservation_period_path(restaurant, reservation_period)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /admin/restaurants/:restaurant_id/reservation_periods/new' do
    it 'returns http success' do
      get new_admin_restaurant_reservation_period_path(restaurant)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /admin/restaurants/:restaurant_id/reservation_periods' do
    let(:valid_params) do
      {
        reservation_period: {
          name: 'lunch',
          display_name: '午餐時段',
          start_time: '11:30',
          end_time: '14:30',
          active: true,
          weekday: 1,
          reservation_interval_minutes: 30
        }
      }
    end

    it 'creates a new reservation period' do
      expect do
        post admin_restaurant_reservation_periods_path(restaurant), params: valid_params
      end.to change(restaurant.reservation_periods, :count).by(1)
    end

    it 'redirects after successful creation' do
      post admin_restaurant_reservation_periods_path(restaurant), params: valid_params
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'GET /admin/restaurants/:restaurant_id/reservation_periods/:id/edit' do
    it 'returns http success' do
      get edit_admin_restaurant_reservation_period_path(restaurant, reservation_period)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'PATCH /admin/restaurants/:restaurant_id/reservation_periods/:id' do
    let(:update_params) do
      {
        reservation_period: {
          display_name: '更新後的名稱'
        }
      }
    end

    it 'updates the reservation period' do
      patch admin_restaurant_reservation_period_path(restaurant, reservation_period), params: update_params
      reservation_period.reload
      expect(reservation_period.display_name).to eq('更新後的名稱')
    end

    it 'redirects after successful update' do
      patch admin_restaurant_reservation_period_path(restaurant, reservation_period), params: update_params
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'DELETE /admin/restaurants/:restaurant_id/reservation_periods/:id' do
    it 'deletes the reservation period' do
      reservation_period
      expect do
        delete admin_restaurant_reservation_period_path(restaurant, reservation_period)
      end.to change(restaurant.reservation_periods, :count).by(-1)
    end

    it 'redirects after deletion' do
      delete admin_restaurant_reservation_period_path(restaurant, reservation_period)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'PATCH /admin/restaurants/:restaurant_id/reservation_periods/:id/toggle_active' do
    it 'toggles reservation period status' do
      original_active = reservation_period.active
      patch toggle_active_admin_restaurant_reservation_period_path(restaurant, reservation_period)
      reservation_period.reload
      expect(reservation_period.active).not_to eq(original_active)
    end

    it 'redirects after toggle' do
      patch toggle_active_admin_restaurant_reservation_period_path(restaurant, reservation_period)
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
        get admin_restaurant_reservation_periods_path(restaurant)
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
        get admin_restaurant_reservation_periods_path(restaurant)
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(admin_restaurants_path)
      end
    end

    context 'when user is not signed in' do
      before { sign_out user }

      it 'redirects to sign in page' do
        get admin_restaurant_reservation_periods_path(restaurant)
        expect(response).to have_http_status(:redirect)
      end
    end
  end
end
