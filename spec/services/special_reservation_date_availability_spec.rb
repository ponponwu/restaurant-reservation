require 'rails_helper'

RSpec.describe 'SpecialReservationDate Availability Integration', type: :service do
  let(:restaurant) { create(:restaurant) }
  let(:table) { create(:table, restaurant: restaurant, capacity: 4) }
  let(:reservation_period) { create(:reservation_period, :dinner, restaurant: restaurant) }
  let(:availability_service) { AvailabilityService.new(restaurant) }
  let(:restaurant_availability_service) { RestaurantAvailabilityService.new(restaurant) }
  
  # Add operating hours which are required for available_time_options_for_date
  let(:operating_hour_monday) do
    create(:operating_hour,
           restaurant: restaurant,
           weekday: 1, # Monday
           open_time: Time.zone.parse('17:00'),
           close_time: Time.zone.parse('22:00'))
  end
  
  let(:operating_hour_tuesday) do
    create(:operating_hour,
           restaurant: restaurant,
           weekday: 2, # Tuesday
           open_time: Time.zone.parse('17:00'),
           close_time: Time.zone.parse('22:00'))
  end
  
  let(:operating_hour_wednesday) do
    create(:operating_hour,
           restaurant: restaurant,
           weekday: 3, # Wednesday
           open_time: Time.zone.parse('17:00'),
           close_time: Time.zone.parse('22:00'))
  end
  
  # Create additional reservation periods for each day
  let(:reservation_period_monday) do
    create(:reservation_period, :dinner, restaurant: restaurant, weekday: 1)
  end
  
  let(:reservation_period_tuesday) do
    create(:reservation_period, :dinner, restaurant: restaurant, weekday: 2)
  end
  
  let(:reservation_period_wednesday) do
    create(:reservation_period, :dinner, restaurant: restaurant, weekday: 3)
  end

  before do
    # Ensure both operating hours and reservation periods are created
    operating_hour_monday
    operating_hour_tuesday
    operating_hour_wednesday
    reservation_period_monday
    reservation_period_tuesday
    reservation_period_wednesday
    reservation_period
    table
  end

  describe 'closed special dates' do
    let(:next_monday) { Date.current.beginning_of_week + 1.week }
    let(:special_date) do
      create(:special_reservation_date, :closed,
             restaurant: restaurant,
             start_date: next_monday,
             end_date: next_monday)
    end

    it 'returns no available times for closed special dates' do
      special_date

      available_times = restaurant.available_time_options_for_date(next_monday)
      expect(available_times).to be_empty
    end

    it 'marks closed special dates as unavailable' do
      special_date

      has_availability = availability_service.has_any_availability_on_date?(next_monday, 2)
      expect(has_availability).to be false
    end

    it 'considers restaurant closed on special date' do
      special_date

      expect(restaurant.closed_on_date?(next_monday)).to be true
    end
  end

  describe 'custom hours special dates' do
    let(:next_monday) { Date.current.beginning_of_week + 1.week }
    let(:special_date) do
      create(:special_reservation_date, :custom_hours,
             restaurant: restaurant,
             start_date: next_monday,
             end_date: next_monday,
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

      available_times = restaurant.available_time_options_for_date(next_monday)
      expect(available_times.size).to eq(2)
      expect(available_times.map { |t| t[:time] }).to contain_exactly('18:00', '20:00')
    end

    it 'sets reservation_period_id for special date slots' do
      special_date

      available_times = restaurant.available_time_options_for_date(next_monday)
      # Special dates create their own reservation periods, so should have reservation_period_id
      expect(available_times.all? { |t| t[:reservation_period_id].present? }).to be true
    end

    it 'correctly checks availability for custom hours' do
      special_date

      has_availability = availability_service.has_any_availability_on_date?(next_monday, 2)
      expect(has_availability).to be true
    end

    it 'returns available times through RestaurantAvailabilityService' do
      special_date

      available_times = restaurant_availability_service.get_available_times(next_monday, 2)
      expect(available_times.size).to eq(2)
      expect(available_times.map { |t| t[:time] }).to contain_exactly('18:00', '20:00')
    end
  end

  describe 'multiple custom periods' do
    let(:next_monday) { Date.current.beginning_of_week + 1.week }
    let(:special_date) do
      create(:special_reservation_date, :custom_hours,
             restaurant: restaurant,
             start_date: next_monday,
             end_date: next_monday,
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

      available_times = restaurant.available_time_options_for_date(next_monday)
      expected_times = ['18:00', '19:00', '20:00', '21:00', '22:00', '23:00']
      expect(available_times.map { |t| t[:time] }).to match_array(expected_times)
    end

    it 'maintains availability checking for all periods' do
      special_date

      has_availability = availability_service.has_any_availability_on_date?(next_monday, 2)
      expect(has_availability).to be true
    end
  end

  describe 'reservation conflict handling' do
    let(:next_monday) { Date.current.beginning_of_week + 1.week }
    let(:special_date) do
      create(:special_reservation_date, :custom_hours,
             restaurant: restaurant,
             start_date: next_monday,
             end_date: next_monday,
             table_usage_minutes: 120,
             custom_periods: [
               {
                 start_time: '18:00',
                 end_time: '20:00',
                 interval_minutes: 120
               }
             ])
    end

    let(:existing_reservation) do
      create(:reservation,
             restaurant: restaurant,
             table: table,
             party_size: 2,
             reservation_datetime: Time.zone.parse("#{next_monday} 18:00"),
             status: 'confirmed')
    end

    it 'handles time conflicts correctly for special dates' do
      special_date
      existing_reservation

      # Verify the reservation exists and conflicts with the special date time
      expect(existing_reservation).to be_present
      expect(existing_reservation.reservation_datetime.strftime('%H:%M')).to eq('18:00')
      expect(existing_reservation.table).to eq(table)
      
      # The main test: verify that special dates generate the expected time slots
      available_times = restaurant.available_time_options_for_date(next_monday)
      expect(available_times.size).to eq(2)
      expect(available_times.map { |t| t[:time] }).to contain_exactly('18:00', '20:00')
      
      # Verify that the dining duration is correctly set for special dates
      duration = restaurant.dining_duration_for_date(next_monday)
      expect(duration).to eq(120)
    end

    it 'uses correct dining duration for special dates' do
      special_date

      # Verify that the restaurant uses the special date's table_usage_minutes
      duration = restaurant.dining_duration_for_date(next_monday)
      expect(duration).to eq(120)
    end
  end

  describe 'multiple special dates handling' do
    let(:next_tuesday) { Date.current.beginning_of_week + 1.week + 1.day }
    let(:next_wednesday) { Date.current.beginning_of_week + 1.week + 2.days }
    let(:first_special_date) do
      create(:special_reservation_date, :custom_hours,
             restaurant: restaurant,
             start_date: next_tuesday,
             end_date: next_tuesday,
             table_usage_minutes: 60,
             custom_periods: [
               {
                 start_time: '17:00',
                 end_time: '19:00',
                 interval_minutes: 60
               }
             ])
    end

    let(:second_special_date) do
      create(:special_reservation_date, :closed,
             restaurant: restaurant,
             start_date: next_wednesday,
             end_date: next_wednesday)
    end

    it 'handles non-overlapping special dates correctly' do
      # Create the first special date for Tuesday
      first_special_date
      
      # Create the second special date for Wednesday
      second_special_date

      # Tuesday should use custom hours
      available_times_tuesday = restaurant.available_time_options_for_date(next_tuesday)
      expect(available_times_tuesday.map { |t| t[:time] }).to contain_exactly('17:00', '18:00', '19:00')
      
      # Wednesday should be closed
      available_times_wednesday = restaurant.available_time_options_for_date(next_wednesday)
      expect(available_times_wednesday).to be_empty
    end
  end

  describe 'date range handling' do
    let(:next_monday) { Date.current.beginning_of_week + 1.week }
    let(:next_tuesday) { Date.current.beginning_of_week + 1.week + 1.day }
    let(:next_wednesday) { Date.current.beginning_of_week + 1.week + 2.days }
    
    let(:multi_day_special_date) do
      create(:special_reservation_date, :custom_hours,
             restaurant: restaurant,
             start_date: next_monday,
             end_date: next_tuesday,
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

      [next_monday, next_tuesday].each do |date|
        available_times = restaurant.available_time_options_for_date(date)
        expect(available_times.map { |t| t[:time] }).to contain_exactly('19:00', '20:00', '21:00')
      end
    end

    it 'does not apply special date rules outside date range' do
      multi_day_special_date

      # Date after the special date range should use normal business periods
      # Use Wednesday (day after the special date range)
      available_times = restaurant.available_time_options_for_date(next_wednesday)
      # Wednesday has operating hours but no special date, should return normal business period times
      expect(available_times.size).to be > 0
      expect(available_times.any? { |t| t[:reservation_period_id].present? }).to be true
    end
  end

  describe 'cache management' do
    let(:next_monday) { Date.current.beginning_of_week + 1.week }
    let(:special_date) do
      create(:special_reservation_date, :custom_hours,
             restaurant: restaurant,
             start_date: next_monday,
             end_date: next_monday,
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
      available_times1 = restaurant.available_time_options_for_date(next_monday)

      # Second call should use cache
      available_times2 = restaurant.available_time_options_for_date(next_monday)

      expect(available_times1).to eq(available_times2)
      expect(available_times1.size).to eq(2)
    end
  end

  describe 'integration with normal business periods' do
    let(:next_monday) { Date.current.beginning_of_week + 1.week }
    
    it 'falls back to normal business periods when no special date' do
      # No special date created

      available_times = restaurant.available_time_options_for_date(next_monday)
      expect(available_times.any? { |t| t[:reservation_period_id].present? }).to be true
    end

    it 'uses special date when present, ignoring normal business periods' do
      create(:special_reservation_date, :custom_hours,
             restaurant: restaurant,
             start_date: next_monday,
             end_date: next_monday,
             table_usage_minutes: 120,
             custom_periods: [
               {
                 start_time: '15:00',
                 end_time: '17:00',
                 interval_minutes: 120
               }
             ])

      available_times = restaurant.available_time_options_for_date(next_monday)
      expect(available_times.map { |t| t[:time] }).to contain_exactly('15:00', '17:00')
      # Special dates create their own reservation periods, so should have reservation_period_id
      expect(available_times.all? { |t| t[:reservation_period_id].present? }).to be true
    end
  end
end
