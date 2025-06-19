require 'rails_helper'

RSpec.describe Admin::ReservationsController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:user) { create(:user, :admin, restaurant: restaurant) }
  
  before do
    sign_in user
    
    # 創建正確的營業時段
    @lunch_period = restaurant.business_periods.create!(
      name: 'lunch',
      display_name: '午餐',
      start_time: '11:30',
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
        datetime = Time.zone.parse('2025-06-19 11:00:00')
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@lunch_period.id)
      end

      it 'returns lunch period for 13:00' do
        datetime = Time.zone.parse('2025-06-19 13:00:00')
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@lunch_period.id)
      end

      it 'returns lunch period for exact start time 11:30' do
        datetime = Time.zone.parse('2025-06-19 11:30:00')
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@lunch_period.id)
      end
    end

    context 'when time is within dinner period' do
      it 'returns dinner period for 19:00' do
        datetime = Time.zone.parse('2025-06-19 19:00:00')
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@dinner_period.id)
      end

      it 'returns dinner period for 20:00' do
        datetime = Time.zone.parse('2025-06-19 20:00:00')
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@dinner_period.id)
      end

      it 'returns dinner period for exact start time 17:30' do
        datetime = Time.zone.parse('2025-06-19 17:30:00')
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@dinner_period.id)
      end
    end

    context 'when time is outside business periods' do
      it 'returns closest period for early morning time 09:00 (closer to lunch)' do
        datetime = Time.zone.parse('2025-06-19 09:00:00')
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@lunch_period.id)
      end

      it 'returns closest period for late night time 23:00 (closer to dinner)' do
        datetime = Time.zone.parse('2025-06-19 23:00:00')
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@dinner_period.id)
      end

      it 'returns closest period for afternoon time 15:30 (between periods)' do
        datetime = Time.zone.parse('2025-06-19 15:30:00')
        result = controller_instance.send(:determine_business_period, datetime)
        # 15:30 should be closer to dinner (17:30-21:30) than lunch (11:30-14:30)
        expect(result).to eq(@dinner_period.id)
      end
    end

    context 'with timezone handling' do
      it 'handles UTC datetime correctly' do
        # UTC 時間 11:00 應該對應台北時間 19:00 (UTC+8)
        datetime = Time.parse('2025-06-19 11:00:00 UTC')
        result = controller_instance.send(:determine_business_period, datetime)
        expect(result).to eq(@dinner_period.id)
      end
    end
  end

  describe 'POST #create with business period determination' do
    let(:reservation_params) do
      {
        customer_name: 'Test Customer',
        customer_phone: '0912345678',
        customer_email: 'test@example.com',
        party_size: 2,
        adults_count: 2,
        children_count: 0,
        reservation_datetime: '2025-06-19T19:00',
        admin_override: false
      }
    end

    it 'correctly assigns dinner period for 19:00 reservation' do
      expect {
        post :create, params: { restaurant_id: restaurant.slug, reservation: reservation_params }
      }.to change(Reservation, :count).by(1)

      reservation = Reservation.last
      expect(reservation.business_period_id).to eq(@dinner_period.id)
      expect(reservation.business_period.name).to eq('dinner')
    end

    it 'correctly assigns lunch period for 12:00 reservation' do
      lunch_params = reservation_params.merge(reservation_datetime: '2025-06-19T12:00')
      
      expect {
        post :create, params: { restaurant_id: restaurant.slug, reservation: lunch_params }
      }.to change(Reservation, :count).by(1)

      reservation = Reservation.last
      expect(reservation.business_period_id).to eq(@lunch_period.id)
      expect(reservation.business_period.name).to eq('lunch')
    end
  end
end