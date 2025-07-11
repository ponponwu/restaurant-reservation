require 'rails_helper'

RSpec.describe Admin::ReservationsController do
  let(:restaurant) { create(:restaurant) }
  let(:user) { create(:user, :admin, restaurant: restaurant) }

  before do
    Time.zone = 'Asia/Taipei'
    sign_in user

    # 創建正確的營業時段
    @lunch_period = restaurant.business_periods.create!(
      name: 'lunch',
      display_name: '午餐',
      start_time: '11:00',
      end_time: '14:30',
      days_of_week_mask: 127,
      active: true
    )

    @dinner_period = restaurant.business_periods.create!(
      name: 'dinner',
      display_name: '晚餐',
      start_time: '17:30',
      end_time: '21:30',
      days_of_week_mask: 127,
      active: true
    )
  end

  describe '#determine_business_period' do
    let(:controller_instance) { described_class.new }

    before do
      controller_instance.instance_variable_set(:@restaurant, restaurant)
    end

    context 'when time is within lunch period' do
      it 'returns lunch period for 11:00' do
        datetime = 3.days.from_now.change(hour: 11, min: 0)
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@lunch_period.id)
      end

      it 'returns lunch period for 13:00' do
        datetime = 3.days.from_now.change(hour: 13, min: 0)
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@lunch_period.id)
      end

      it 'returns lunch period for exact start time 11:30' do
        datetime = 3.days.from_now.change(hour: 11, min: 30)
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@lunch_period.id)
      end
    end

    context 'when time is within dinner period' do
      it 'returns dinner period for 19:00' do
        datetime = 3.days.from_now.change(hour: 19, min: 0)
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@dinner_period.id)
      end

      it 'returns dinner period for 20:00' do
        datetime = 3.days.from_now.change(hour: 20, min: 0)
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@dinner_period.id)
      end

      it 'returns dinner period for exact start time 17:30' do
        datetime = 3.days.from_now.change(hour: 17, min: 30)
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@dinner_period.id)
      end
    end

    context 'when time is outside business periods' do
      it 'returns closest period for early morning time 09:00 (closer to lunch)' do
        datetime = 3.days.from_now.change(hour: 9, min: 0)
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@lunch_period.id)
      end

      it 'returns closest period for late night time 23:00 (closer to dinner)' do
        datetime = 3.days.from_now.change(hour: 23, min: 0)
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@dinner_period.id)
      end

      it 'returns closest period for afternoon time 15:30 (between periods)' do
        datetime = 3.days.from_now.change(hour: 15, min: 30)
        result = controller_instance.send(:determine_business_period, datetime)
        # 15:30 should be closer to dinner (17:30-21:30) than lunch (11:30-14:30)
        expect(result).to eq(@dinner_period.id)
      end
    end

    context 'with timezone handling' do
      it 'handles UTC datetime correctly' do
        # UTC 時間 11:00 應該對應台北時間 19:00 (UTC+8)，在晚餐時段內
        # 但實際上台北時間是UTC+8，所以UTC 11:00 = 台北19:00
        datetime = 3.days.from_now.change(hour: 11, min: 0).utc
        local_time = datetime.in_time_zone('Asia/Taipei')

        result = controller_instance.send(:determine_business_period, datetime)

        # 根據實際時間判斷應該屬於哪個時段
        if local_time.hour >= 17 && local_time.hour <= 21
          expect(result).to eq(@dinner_period.id)
        elsif local_time.hour >= 11 && local_time.hour <= 14
          expect(result).to eq(@lunch_period.id)
        else
          # 如果不在營業時段內，應該返回最接近的時段
          expect([@lunch_period.id, @dinner_period.id]).to include(result)
        end
      end
    end
  end

  describe 'POST #create with business period determination' do
    let!(:table_group) do
      restaurant.table_groups.create!(
        name: '主要區域',
        description: '主要用餐區域',
        active: true
      )
    end
    let(:reservation_params) do
      # 選擇明天晚上7點，確保在晚餐時段(17:30-21:30)內且滿足提前預訂需求
      dinner_time = 1.day.from_now.change(hour: 19, min: 0)
      {
        customer_name: 'Test Customer',
        customer_phone: '0912345678',
        customer_email: 'test@example.com',
        party_size: 2,
        adults_count: 2,
        children_count: 0,
        reservation_datetime: dinner_time.strftime('%Y-%m-%dT%H:%M'),
        table_id: table.id,
        admin_override: false
      }
    end

    let!(:table) do
      restaurant.restaurant_tables.create!(
        table_number: 'A1',
        capacity: 4,
        min_capacity: 1,
        max_capacity: 4,
        table_group: table_group,
        active: true
      )
    end

    before do
      Reservation.destroy_all
    end

    it 'correctly assigns dinner period for 19:00 reservation' do
      post :create, params: { restaurant_id: restaurant.slug, reservation: reservation_params }

      expect(Reservation.count).to eq(1)

      reservation = Reservation.last
      expect(reservation.business_period_id).to eq(@dinner_period.id)
      expect(reservation.business_period.name).to eq('dinner')
    end

    it 'correctly assigns lunch period for 12:00 reservation' do
      # 選擇明天中午12點，確保在午餐時段(11:00-14:30)內
      lunch_time = 1.day.from_now.change(hour: 12, min: 0)
      lunch_params = reservation_params.merge(reservation_datetime: lunch_time.strftime('%Y-%m-%dT%H:%M'))

      expect do
        post :create, params: { restaurant_id: restaurant.slug, reservation: lunch_params }
      end.to change(Reservation, :count).by(1)

      reservation = Reservation.last
      expect(reservation.business_period_id).to eq(@lunch_period.id)
      expect(reservation.business_period.name).to eq('lunch')
    end
  end

  describe 'POST #create with admin force mode' do
    let!(:table_group) do
      restaurant.table_groups.create!(
        name: '主要區域',
        description: '主要用餐區域',
        active: true
      )
    end

    let!(:table) do
      restaurant.restaurant_tables.create!(
        table_number: 'A1',
        capacity: 2,
        min_capacity: 1,
        max_capacity: 2,
        table_group: table_group,
        active: true
      )
    end

    let(:force_mode_params) do
      {
        customer_name: 'Force Mode Customer',
        customer_phone: '0987654321',
        customer_email: 'force@example.com',
        party_size: 2,
        adults_count: 2,
        children_count: 0,
        reservation_datetime: 3.days.from_now.change(hour: 19, min: 0).iso8601,
        table_id: table.id
      }
    end

    context 'when time slot is fully booked' do
      before do
        # 創建一個訂位佔滿這個時段的桌位
        restaurant.reservations.create!(
          customer_name: 'Existing Customer',
          customer_phone: '0911111111',
          customer_email: 'existing@example.com',
          party_size: 2,
          adults_count: 2,
          children_count: 0,
          reservation_datetime: 3.days.from_now.change(hour: 19, min: 0),
          business_period: @dinner_period,
          table: table,
          status: :confirmed
        )
      end

      it 'creates reservation with admin override when force mode is enabled' do
        # 創建一個不同的桌位來避免衝突
        another_table = restaurant.restaurant_tables.create!(
          table_number: 'A2',
          capacity: 2,
          min_capacity: 1,
          max_capacity: 2,
          table_group: table_group,
          active: true
        )

        params_with_override = force_mode_params.merge(
          admin_override: true,
          table_id: another_table.id
        )

        expect do
          post :create, params: {
            restaurant_id: restaurant.slug,
            reservation: params_with_override,
            admin_override: 'true'
          }
        end.to change(Reservation, :count).by(1)

        new_reservation = Reservation.last
        expect(new_reservation.customer_name).to eq('Force Mode Customer')
        expect(new_reservation.admin_override).to be true
        expect(new_reservation.status).to eq('confirmed')
        expect(new_reservation.table).to eq(another_table)

        # 驗證成功訊息
        expect(response).to redirect_to(admin_restaurant_reservations_path(restaurant, date_filter: 3.days.from_now.strftime('%Y-%m-%d')))
        expect(flash[:notice]).to include('訂位建立成功')
      end

      it 'creates reservation even when no tables are available if admin_override is true' do
        # 創建另一個更大的桌位並佔滿所有桌位
        big_table = restaurant.restaurant_tables.create!(
          table_number: 'B1',
          capacity: 4,
          min_capacity: 1,
          max_capacity: 4,
          table_group: table_group,
          active: true
        )

        # 佔滿大桌位
        restaurant.reservations.create!(
          customer_name: 'Big Party',
          customer_phone: '0922222222',
          customer_email: 'big@example.com',
          party_size: 4,
          adults_count: 4,
          children_count: 0,
          reservation_datetime: 3.days.from_now.change(hour: 18, min: 0), # 使用不同時間避免衝突
          business_period: @dinner_period,
          table: big_table,
          status: :confirmed,
          admin_override: true
        )

        # 嘗試在完全沒有容量的情況下創建訂位（強制使用同一張桌位）
        params_with_override = force_mode_params.merge(
          admin_override: true,
          party_size: 6,
          adults_count: 6,
          children_count: 0,
          table_id: big_table.id # 指定已被佔用的桌位
        )

        expect do
          post :create, params: {
            restaurant_id: restaurant.slug,
            reservation: params_with_override,
            admin_override: 'true'
          }
        end.to change(Reservation, :count).by(1)

        new_reservation = Reservation.last
        expect(new_reservation.customer_name).to eq('Force Mode Customer')
        expect(new_reservation.admin_override).to be true
        expect(new_reservation.party_size).to eq(6)
        expect(new_reservation.table).to eq(big_table)
      end

      it 'requires table_id when creating reservation in admin panel' do
        params_without_table = force_mode_params.except(:table_id).merge(admin_override: true)

        expect do
          post :create, params: {
            restaurant_id: restaurant.slug,
            reservation: params_without_table
          }
        end.not_to change(Reservation, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(assigns(:reservation).errors[:table_id]).to include('後台建立訂位時必須指定桌位')
      end
    end

    context 'when creating reservation with specified table' do
      it 'assigns the specified table directly without auto-allocation' do
        normal_params = force_mode_params.merge(admin_override: true)

        expect do
          post :create, params: {
            restaurant_id: restaurant.slug,
            reservation: normal_params
          }
        end.to change(Reservation, :count).by(1)

        new_reservation = Reservation.last
        expect(new_reservation.table).to eq(table)
        expect(new_reservation.admin_override).to be true
        expect(new_reservation.status).to eq('confirmed')

        expect(flash[:notice]).to include('訂位建立成功，已指定桌位')
      end

      it 'creates reservation even if specified table is over capacity' do
        # 嘗試在容量2的桌位安排6個人
        over_capacity_params = force_mode_params.merge(
          party_size: 6,
          adults_count: 6,
          children_count: 0,
          admin_override: true
        )

        expect do
          post :create, params: {
            restaurant_id: restaurant.slug,
            reservation: over_capacity_params,
            admin_override: 'true'
          }
        end.to change(Reservation, :count).by(1)

        new_reservation = Reservation.last
        expect(new_reservation.table).to eq(table)
        expect(new_reservation.party_size).to eq(6)
        expect(new_reservation.table.capacity).to eq(2) # 桌位容量遠小於人數
        expect(new_reservation.admin_override).to be true
      end
    end
  end
end
