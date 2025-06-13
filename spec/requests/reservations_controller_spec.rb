require 'rails_helper'

RSpec.describe ReservationsController, type: :request do
  let(:restaurant) { create(:restaurant) }
  let(:reservation_policy) { restaurant.reservation_policy || restaurant.create_reservation_policy! }

  describe 'reservation enabled/disabled protection' do
    context 'when reservation is enabled' do
      before do
        reservation_policy.update!(reservation_enabled: true)
      end

      describe 'GET #new' do
        it 'allows access to reservation form' do
          get new_restaurant_reservation_path(restaurant.slug)
          expect(response).to have_http_status(:success)
        end
      end

      describe 'POST #create' do
        let(:valid_params) do
          {
            reservation: {
              customer_name: '測試客戶',
              customer_phone: '0912345678',
              customer_email: 'test@example.com',
              party_size: 4,
              reservation_datetime: 2.days.from_now.strftime('%Y-%m-%d %H:%M')
            }
          }
        end

        it 'allows reservation creation' do
          post restaurant_reservations_path(restaurant.slug), params: valid_params
          expect(response).to have_http_status(:redirect)
        end
      end
    end

    context 'when reservation is disabled' do
      before do
        reservation_policy.update!(reservation_enabled: false)
      end

      describe 'GET #new' do
        it 'redirects with disabled message' do
          get new_restaurant_reservation_path(restaurant.slug)
          expect(response).to have_http_status(:redirect)
          follow_redirect!
          expect(response.body).to include('線上訂位功能暫停服務')
        end
      end

      describe 'POST #create' do
        let(:valid_params) do
          {
            reservation: {
              customer_name: '測試客戶',
              customer_phone: '0912345678',
              customer_email: 'test@example.com',
              party_size: 4,
              reservation_datetime: 2.days.from_now.strftime('%Y-%m-%d %H:%M')
            }
          }
        end

        it 'redirects and prevents reservation creation' do
          expect {
            post restaurant_reservations_path(restaurant.slug), params: valid_params
          }.not_to change(Reservation, :count)
          
          expect(response).to have_http_status(:redirect)
          follow_redirect!
          expect(response.body).to include('線上訂位功能暫停服務')
        end

        context 'with AJAX request' do
          it 'returns JSON error response' do
            post restaurant_reservations_path(restaurant.slug), 
                 params: valid_params,
                 headers: { 'Accept' => 'application/json' }
            
            expect(response).to have_http_status(:service_unavailable)
            json_response = JSON.parse(response.body)
            expect(json_response['error']).to include('線上訂位功能暫停服務')
          end
        end
      end
    end
  end

  describe 'phone booking limits protection' do
    let(:phone_number) { '0912345678' }
    
    before do
      reservation_policy.update!(
        reservation_enabled: true,
        max_bookings_per_phone: 2,
        phone_limit_period_days: 30
      )
    end

    context 'when under phone booking limit' do
      before do
        # 創建1個現有訂位
        create(:reservation, 
               restaurant: restaurant,
               customer_phone: phone_number,
               reservation_datetime: 5.days.from_now,
               status: :confirmed)
      end

      it 'allows new reservation' do
        valid_params = {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: phone_number,
            customer_email: 'test@example.com',
            party_size: 4,
            reservation_datetime: 7.days.from_now.strftime('%Y-%m-%d %H:%M')
          }
        }

        expect {
          post restaurant_reservations_path(restaurant.slug), params: valid_params
        }.to change(Reservation, :count).by(1)
      end
    end

    context 'when at phone booking limit' do
      before do
        # 創建2個現有訂位（達到限制）
        create_list(:reservation, 2,
                   restaurant: restaurant,
                   customer_phone: phone_number,
                   reservation_datetime: 5.days.from_now,
                   status: :confirmed)
      end

      it 'prevents new reservation' do
        valid_params = {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: phone_number,
            customer_email: 'test@example.com',
            party_size: 4,
            reservation_datetime: 7.days.from_now.strftime('%Y-%m-%d %H:%M')
          }
        }

        expect {
          post restaurant_reservations_path(restaurant.slug), params: valid_params
        }.not_to change(Reservation, :count)
        
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns appropriate error message' do
        valid_params = {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: phone_number,
            customer_email: 'test@example.com',
            party_size: 4,
            reservation_datetime: 7.days.from_now.strftime('%Y-%m-%d %H:%M')
          }
        }

        post restaurant_reservations_path(restaurant.slug), params: valid_params
        expect(response.body).to include('訂位次數已達上限')
      end
    end

    context 'cancelled reservations do not count towards limit' do
      before do
        # 創建2個已取消的訂位（不應計入限制）
        create_list(:reservation, 2,
                   restaurant: restaurant,
                   customer_phone: phone_number,
                   reservation_datetime: 5.days.from_now,
                   status: :cancelled)
      end

      it 'allows new reservation' do
        valid_params = {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: phone_number,
            customer_email: 'test@example.com',
            party_size: 4,
            reservation_datetime: 7.days.from_now.strftime('%Y-%m-%d %H:%M')
          }
        }

        expect {
          post restaurant_reservations_path(restaurant.slug), params: valid_params
        }.to change(Reservation, :count).by(1)
      end
    end
  end

  describe 'party size validation' do
    before do
      reservation_policy.update!(
        reservation_enabled: true,
        min_party_size: 2,
        max_party_size: 8
      )
    end

    context 'with valid party size' do
      it 'allows reservation' do
        valid_params = {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: '0912345678',
            customer_email: 'test@example.com',
            party_size: 4,
            reservation_datetime: 2.days.from_now.strftime('%Y-%m-%d %H:%M')
          }
        }

        expect {
          post restaurant_reservations_path(restaurant.slug), params: valid_params
        }.to change(Reservation, :count).by(1)
      end
    end

    context 'with party size too small' do
      it 'prevents reservation' do
        invalid_params = {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: '0912345678',
            customer_email: 'test@example.com',
            party_size: 1,
            reservation_datetime: 2.days.from_now.strftime('%Y-%m-%d %H:%M')
          }
        }

        expect {
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        }.not_to change(Reservation, :count)
        
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with party size too large' do
      it 'prevents reservation' do
        invalid_params = {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: '0912345678',
            customer_email: 'test@example.com',
            party_size: 12,
            reservation_datetime: 2.days.from_now.strftime('%Y-%m-%d %H:%M')
          }
        }

        expect {
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        }.not_to change(Reservation, :count)
        
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'advance booking validation' do
    before do
      reservation_policy.update!(
        reservation_enabled: true,
        advance_booking_days: 14,
        minimum_advance_hours: 24
      )
    end

    context 'booking too far in advance' do
      it 'prevents reservation' do
        invalid_params = {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: '0912345678',
            customer_email: 'test@example.com',
            party_size: 4,
            reservation_datetime: 20.days.from_now.strftime('%Y-%m-%d %H:%M')
          }
        }

        expect {
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        }.not_to change(Reservation, :count)
      end
    end

    context 'booking too close to current time' do
      it 'prevents reservation' do
        invalid_params = {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: '0912345678',
            customer_email: 'test@example.com',
            party_size: 4,
            reservation_datetime: 12.hours.from_now.strftime('%Y-%m-%d %H:%M')
          }
        }

        expect {
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        }.not_to change(Reservation, :count)
      end
    end
  end
end 