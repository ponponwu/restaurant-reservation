require 'rails_helper'

RSpec.describe ReservationsController do
  let(:restaurant) { create(:restaurant) }
  let(:reservation_policy) { restaurant.reservation_policy || restaurant.create_reservation_policy! }

  before do
    # 確保餐廳有基本的營業設定 - 設定為全週營業以避免測試受當前日期影響
    unless restaurant.reservation_periods.any?
      create(:reservation_period,
             restaurant: restaurant,
             days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
    end

    # 確保餐廳有桌位群組和桌位
    unless restaurant.table_groups.any?
      table_group = restaurant.table_groups.create!(
        name: '主要區域',
        description: '主要用餐區域',
        active: true
      )

      restaurant.restaurant_tables.create!(
        table_number: 'A1',
        capacity: 4,
        min_capacity: 1,
        max_capacity: 4,
        table_group: table_group,
        active: true
      )

      # 創建第二個桌位以確保有足夠容量進行多個訂位測試
      restaurant.restaurant_tables.create!(
        table_number: 'A2',
        capacity: 4,
        min_capacity: 1,
        max_capacity: 4,
        table_group: table_group,
        active: true
      )

      # 確保餐廳總容量被正確計算和快取
      restaurant.update_cached_capacity
    end
  end

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
              party_size: 4
            },
            date: 2.days.from_now.strftime('%Y-%m-%d'),
            time_slot: '18:00',
            adults: 3,
            children: 1,
            reservation_period_id: restaurant.reservation_periods.first&.id
          }
        end

        it 'allows reservation creation' do
          post restaurant_reservations_path(restaurant.slug), params: valid_params

          # 調試信息：如果不是重定向，顯示錯誤
          if response.status != 302
            puts "Response status: #{response.status}"
            puts "Response body: #{response.body}" if response.body.present?
            if assigns(:reservation) && assigns(:reservation).errors.any?
              puts "Reservation errors: #{assigns(:reservation).errors.full_messages}"
            end
          end

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
              party_size: 4
            },
            date: 2.days.from_now.strftime('%Y-%m-%d'),
            time_slot: '18:00',
            adults: 3,
            children: 1,
            reservation_period_id: restaurant.reservation_periods.first&.id
          }
        end

        it 'redirects and prevents reservation creation' do
          expect do
            post restaurant_reservations_path(restaurant.slug), params: valid_params
          end.not_to change(Reservation, :count)

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
            json_response = response.parsed_body
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
        # 創建1個現有訂位，確保分配到桌位
        table = restaurant.restaurant_tables.first
        create(:reservation,
               restaurant: restaurant,
               table: table,
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
            party_size: 4
          },
          date: 7.days.from_now.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 4,
          children: 0,
          reservation_period_id: restaurant.reservation_periods.first&.id
        }

        expect do
          post restaurant_reservations_path(restaurant.slug), params: valid_params
        end.to change(Reservation, :count).by(1)
      end
    end

    context 'when at phone booking limit' do
      before do
        # 創建2個現有訂位（達到限制），確保分配到不同桌位或不同時間
        tables = restaurant.restaurant_tables.limit(2)
        create(:reservation,
               restaurant: restaurant,
               table: tables.first,
               customer_phone: phone_number,
               reservation_datetime: 5.days.from_now.change(hour: 18, min: 0),
               status: :confirmed)
        create(:reservation,
               restaurant: restaurant,
               table: tables.second,
               customer_phone: phone_number,
               reservation_datetime: 6.days.from_now.change(hour: 18, min: 0),
               status: :confirmed)
      end

      it 'prevents new reservation' do
        valid_params = {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: phone_number,
            customer_email: 'test@example.com',
            party_size: 4
          },
          date: 7.days.from_now.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 4,
          children: 0,
          reservation_period_id: restaurant.reservation_periods.first&.id
        }

        expect do
          post restaurant_reservations_path(restaurant.slug), params: valid_params
        end.not_to change(Reservation, :count)

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
        expect(response.body).to include('訂位失敗，請聯繫餐廳')
      end
    end

    context 'cancelled reservations do not count towards limit' do
      before do
        # 創建2個已取消的訂位（不應計入限制）
        tables = restaurant.restaurant_tables.limit(2)
        create(:reservation,
               restaurant: restaurant,
               table: tables.first,
               customer_phone: phone_number,
               reservation_datetime: 5.days.from_now.change(hour: 18, min: 0),
               status: :cancelled)
        create(:reservation,
               restaurant: restaurant,
               table: tables.second,
               customer_phone: phone_number,
               reservation_datetime: 6.days.from_now.change(hour: 18, min: 0),
               status: :cancelled)
      end

      it 'allows new reservation' do
        valid_params = {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: phone_number,
            customer_email: 'test@example.com',
            party_size: 4
          },
          date: 7.days.from_now.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 4,
          children: 0,
          reservation_period_id: restaurant.reservation_periods.first&.id
        }

        expect do
          post restaurant_reservations_path(restaurant.slug), params: valid_params
        end.to change(Reservation, :count).by(1)
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
            party_size: 4
          },
          date: 2.days.from_now.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 4,
          children: 0,
          reservation_period_id: restaurant.reservation_periods.first&.id
        }

        expect do
          post restaurant_reservations_path(restaurant.slug), params: valid_params
        end.to change(Reservation, :count).by(1)
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

        expect do
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        end.not_to change(Reservation, :count)

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

        expect do
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        end.not_to change(Reservation, :count)

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

        expect do
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        end.not_to change(Reservation, :count)
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

        expect do
          post restaurant_reservations_path(restaurant.slug), params: invalid_params
        end.not_to change(Reservation, :count)
      end
    end
  end

  describe 'blacklist protection and sensitive error handling' do
    let(:blacklisted_phone) { '0987654321' }
    let(:normal_phone) { '0912345678' }

    before do
      reservation_policy.update!(reservation_enabled: true)
      # 創建黑名單記錄
      create(:blacklist,
             restaurant: restaurant,
             customer_phone: blacklisted_phone,
             reason: 'Test blacklist reason')
    end

    describe 'POST #create with blacklisted phone' do
      let(:blacklisted_params) do
        {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: blacklisted_phone,
            customer_email: 'test@example.com',
            party_size: 4
          },
          date: 2.days.from_now.to_date.to_s,
          time_slot: '18:00',
          adults: 3,
          children: 1,
          reservation_period_id: restaurant.reservation_periods.first&.id
        }
      end

      it 'prevents reservation creation' do
        expect do
          post restaurant_reservations_path(restaurant.slug), params: blacklisted_params
        end.not_to change(Reservation, :count)
      end

      it 'returns unprocessable entity status' do
        post restaurant_reservations_path(restaurant.slug), params: blacklisted_params
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'shows generic error message instead of revealing blacklist status' do
        post restaurant_reservations_path(restaurant.slug), params: blacklisted_params
        expect(response.body).to include('訂位失敗，請聯繫餐廳')
        expect(response.body).not_to include('黑名單')
        expect(response.body).not_to include('blacklist')
      end

      it 'does not show detailed blacklist reason' do
        post restaurant_reservations_path(restaurant.slug), params: blacklisted_params
        expect(response.body).not_to include('Test blacklist reason')
      end
    end

    describe 'POST #create with phone booking limit exceeded' do
      let(:limited_phone) { '0966666666' }
      let(:limited_params) do
        {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: limited_phone,
            customer_email: 'test@example.com',
            party_size: 2
          },
          date: 3.days.from_now.to_date.to_s,
          time_slot: '19:00',
          adults: 2,
          children: 0,
          reservation_period_id: restaurant.reservation_periods.first&.id
        }
      end

      before do
        reservation_policy.update!(
          max_bookings_per_phone: 1,
          phone_limit_period_days: 30
        )

        # 創建一個現有訂位達到限制，確保分配到桌位
        table = restaurant.restaurant_tables.first
        create(:reservation,
               restaurant: restaurant,
               table: table,
               customer_phone: limited_phone,
               reservation_datetime: 5.days.from_now,
               status: :confirmed)
      end

      it 'prevents reservation creation' do
        expect do
          post restaurant_reservations_path(restaurant.slug), params: limited_params
        end.not_to change(Reservation, :count)
      end

      it 'shows generic error message instead of revealing specific limit' do
        post restaurant_reservations_path(restaurant.slug), params: limited_params
        expect(response.body).to include('訂位失敗，請聯繫餐廳')
        expect(response.body).not_to include('訂位次數已達上限')
        expect(response.body).not_to include('limit')
      end
    end

    describe 'POST #create with normal phone (no restrictions)' do
      let(:normal_params) do
        {
          reservation: {
            customer_name: '正常客戶',
            customer_phone: normal_phone,
            customer_email: 'normal@example.com',
            party_size: 2
          },
          date: 2.days.from_now.to_date.to_s,
          time_slot: '18:30',
          adults: 2,
          children: 0,
          reservation_period_id: restaurant.reservation_periods.first&.id
        }
      end

      before do
        # 確保餐廳有營業時段和桌位
        create(:reservation_period, restaurant: restaurant) unless restaurant.reservation_periods.any?
        unless restaurant.restaurant_tables.any?
          table_group = restaurant.table_groups.first || restaurant.table_groups.create!(
            name: '主要區域',
            description: '主要用餐區域',
            active: true
          )
          create(:table, restaurant: restaurant, table_group: table_group)
        end
      end

      it 'allows reservation creation' do
        expect do
          post restaurant_reservations_path(restaurant.slug), params: normal_params
        end.to change(Reservation, :count).by(1)
      end

      it 'redirects to restaurant page on success' do
        post restaurant_reservations_path(restaurant.slug), params: normal_params
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(restaurant_public_path(restaurant.slug))
      end
    end

    describe 'error message display format' do
      let(:blacklisted_params) do
        {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: blacklisted_phone,
            customer_email: 'test@example.com',
            party_size: 4
          },
          date: 2.days.from_now.to_date.to_s,
          time_slot: '18:00',
          adults: 3,
          children: 1,
          reservation_period_id: restaurant.reservation_periods.first&.id
        }
      end

      it 'shows simplified error message without title or list styling' do
        post restaurant_reservations_path(restaurant.slug), params: blacklisted_params

        # 應該包含錯誤訊息
        expect(response.body).to include('訂位失敗，請聯繫餐廳')

        # 不應該包含錯誤標題
        expect(response.body).not_to include('預約時發生錯誤')
        expect(response.body).not_to include('發生錯誤')

        # 不應該有重複的錯誤訊息
        error_count = response.body.scan(/訂位失敗，請聯繫餐廳/).length
        expect(error_count).to eq(1)
      end
    end
  end
end
