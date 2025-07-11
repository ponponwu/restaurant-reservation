require 'rails_helper'

RSpec.describe 'SpecialReservationDate Availability Integration', type: :service do
  let(:restaurant) { create(:restaurant) }
  let(:table) { create(:table, restaurant: restaurant, capacity: 4) }
  let(:business_period) { create(:business_period, :dinner, restaurant: restaurant) }
  let(:availability_service) { AvailabilityService.new(restaurant) }
  let(:restaurant_availability_service) { RestaurantAvailabilityService.new(restaurant) }

  before do
    # Ensure business period and table are created
    business_period
    table
  end

  describe 'closed special dates' do
    let(:special_date) do
      create(:special_reservation_date, :closed,
             restaurant: restaurant,
             start_date: Date.current + 1.day,
             end_date: Date.current + 1.day)
    end

    it 'returns no available times for closed special dates' do
      special_date
      
      available_times = restaurant.available_time_options_for_date(Date.current + 1.day)
      expect(available_times).to be_empty
    end

    it 'marks closed special dates as unavailable' do
      special_date
      
      has_availability = availability_service.has_any_availability_on_date?(Date.current + 1.day, 2)
      expect(has_availability).to be false
    end

    it 'considers restaurant closed on special date' do
      special_date
      
      expect(restaurant.closed_on_date?(Date.current + 1.day)).to be true
    end
  end

  describe 'custom hours special dates' do
    let(:special_date) do
      create(:special_reservation_date, :custom_hours,
             restaurant: restaurant,
             start_date: Date.current + 1.day,
             end_date: Date.current + 1.day,
             table_usage_minutes: 120,
             custom_periods: [
               {
                 start_time: '18:00',
                 end_time: '20:00',
                 interval_minutes: 120
               }
             ])
    end

    it 'generates time slots from custom periods' do
      special_date
      
      available_times = restaurant.available_time_options_for_date(Date.current + 1.day)
      expect(available_times.size).to eq(2)
      expect(available_times.map { |t| t[:time] }).to contain_exactly('18:00', '20:00')
    end

    it 'sets business_period_id to nil for special date slots' do
      special_date
      
      available_times = restaurant.available_time_options_for_date(Date.current + 1.day)
      expect(available_times.all? { |t| t[:business_period_id].nil? }).to be true
    end

    it 'correctly checks availability for custom hours' do
      special_date
      
      has_availability = availability_service.has_any_availability_on_date?(Date.current + 1.day, 2)
      expect(has_availability).to be true
    end

    it 'returns available times through RestaurantAvailabilityService' do
      special_date
      
      available_times = restaurant_availability_service.get_available_times(Date.current + 1.day, 2)
      expect(available_times.size).to eq(2)
      expect(available_times.map { |t| t[:time] }).to contain_exactly('18:00', '20:00')
    end
  end

  describe 'multiple custom periods' do
    let(:special_date) do
      create(:special_reservation_date, :custom_hours,
             restaurant: restaurant,
             start_date: Date.current + 1.day,
             end_date: Date.current + 1.day,
             table_usage_minutes: 90,
             custom_periods: [
               {
                 start_time: '18:00',
                 end_time: '20:00',
                 interval_minutes: 60
               },
               {
                 start_time: '21:00',
                 end_time: '23:00',
                 interval_minutes: 60
               }
             ])
    end

    it 'generates time slots for all periods' do
      special_date
      
      available_times = restaurant.available_time_options_for_date(Date.current + 1.day)
      expected_times = ['18:00', '19:00', '20:00', '21:00', '22:00', '23:00']
      expect(available_times.map { |t| t[:time] }).to contain_exactly(*expected_times)
    end

    it 'maintains availability checking for all periods' do
      special_date
      
      has_availability = availability_service.has_any_availability_on_date?(Date.current + 1.day, 2)
      expect(has_availability).to be true
    end
  end

  describe 'reservation conflict handling' do
    let(:special_date) do
      create(:special_reservation_date, :custom_hours,
             restaurant: restaurant,
             start_date: Date.current + 1.day,
             end_date: Date.current + 1.day,
             table_usage_minutes: 120,
             custom_periods: [
               {
                 start_time: '18:00',
                 end_time: '20:00',
                 interval_minutes: 60
               }
             ])
    end

    let(:existing_reservation) do
      create(:reservation,
             restaurant: restaurant,
             table: table,
             business_period: business_period,
             reservation_datetime: Time.zone.parse("#{Date.current + 1.day} 18:00"),
             status: 'confirmed')
    end

    it 'handles time conflicts correctly for special dates' do
      special_date
      existing_reservation
      
      # 18:00 slot should be unavailable due to existing reservation
      available_slots = availability_service.get_available_slots_by_period(Date.current + 1.day, 2, 2, 0)
      
      # Should have fewer available slots due to conflict
      expect(available_slots.size).to be < 3
    end

    it 'uses correct dining duration for special dates' do
      special_date
      
      # Verify that the restaurant uses the special date's table_usage_minutes
      duration = restaurant.dining_duration_for_date(Date.current + 1.day)
      expect(duration).to eq(120)
    end
  end

  describe 'priority handling' do
    let(:low_priority_special_date) do
      create(:special_reservation_date, :custom_hours,
             restaurant: restaurant,
             start_date: Date.current + 2.days,
             end_date: Date.current + 2.days,
             priority: 1,
             table_usage_minutes: 60,
             custom_periods: [
               {
                 start_time: '17:00',
                 end_time: '19:00',
                 interval_minutes: 60
               }
             ])
    end

    let(:high_priority_special_date) do
      create(:special_reservation_date, :closed,
             restaurant: restaurant,
             start_date: Date.current + 2.days,
             end_date: Date.current + 2.days,
             priority: 10)
    end

    it 'uses highest priority special date' do
      # Create the low priority one first
      low_priority_special_date
      
      # Then deactivate it and create the high priority one
      low_priority_special_date.update!(active: false)
      high_priority_special_date
      
      # Should use the high priority (closed) special date
      available_times = restaurant.available_time_options_for_date(Date.current + 2.days)
      expect(available_times).to be_empty
    end
  end

  describe 'date range handling' do
    let(:multi_day_special_date) do
      create(:special_reservation_date, :custom_hours,
             restaurant: restaurant,
             start_date: Date.current + 1.day,
             end_date: Date.current + 3.days,
             table_usage_minutes: 90,
             custom_periods: [
               {
                 start_time: '19:00',
                 end_time: '21:00',
                 interval_minutes: 60
               }
             ])
    end

    it 'applies special date rules to entire date range' do
      multi_day_special_date
      
      (Date.current + 1.day..Date.current + 3.days).each do |date|
        available_times = restaurant.available_time_options_for_date(date)
        expect(available_times.map { |t| t[:time] }).to contain_exactly('19:00', '20:00', '21:00')
      end
    end

    it 'does not apply special date rules outside date range' do
      multi_day_special_date
      
      # Date before the special date range should use normal business periods
      available_times = restaurant.available_time_options_for_date(Date.current)
      expect(available_times.any? { |t| t[:business_period_id].present? }).to be true
    end
  end

  describe 'cache management' do
    let(:special_date) do
      create(:special_reservation_date, :custom_hours,
             restaurant: restaurant,
             start_date: Date.current + 1.day,
             end_date: Date.current + 1.day,
             table_usage_minutes: 120,
             custom_periods: [
               {
                 start_time: '18:00',
                 end_time: '20:00',
                 interval_minutes: 120
               }
             ])
    end

    it 'caches special date time options correctly' do
      special_date
      
      # First call should cache the result
      available_times1 = restaurant.available_time_options_for_date(Date.current + 1.day)
      
      # Second call should use cache
      available_times2 = restaurant.available_time_options_for_date(Date.current + 1.day)
      
      expect(available_times1).to eq(available_times2)
      expect(available_times1.size).to eq(2)
    end
  end

  describe 'integration with normal business periods' do
    it 'falls back to normal business periods when no special date' do
      # No special date created
      
      available_times = restaurant.available_time_options_for_date(Date.current + 1.day)
      expect(available_times.any? { |t| t[:business_period_id].present? }).to be true
    end

    it 'uses special date when present, ignoring normal business periods' do
      special_date = create(:special_reservation_date, :custom_hours,
                           restaurant: restaurant,
                           start_date: Date.current + 1.day,
                           end_date: Date.current + 1.day,
                           table_usage_minutes: 120,
                           custom_periods: [
                             {
                               start_time: '15:00',
                               end_time: '17:00',
                               interval_minutes: 120
                             }
                           ])
      
      available_times = restaurant.available_time_options_for_date(Date.current + 1.day)
      expect(available_times.map { |t| t[:time] }).to contain_exactly('15:00', '17:00')
      expect(available_times.all? { |t| t[:business_period_id].nil? }).to be true
    end
  end
end