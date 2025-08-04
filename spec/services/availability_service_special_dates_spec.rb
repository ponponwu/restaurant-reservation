require 'rails_helper'

RSpec.describe AvailabilityService, type: :service do
  let(:restaurant) { create(:restaurant, :with_reservation_periods, :with_tables) }
  let(:service) { described_class.new(restaurant) }
  let(:special_date) { Date.current + 7.days } # 7 days from now

  before do
    # Clear any existing special dates
    restaurant.special_reservation_dates.destroy_all
  end

  describe 'special dates availability checking' do
    context 'when special date has custom hours' do
      let!(:special_reservation_date) do
        create(:special_reservation_date,
               restaurant: restaurant,
               start_date: special_date,
               end_date: special_date,
               operation_mode: 'custom_hours',
               table_usage_minutes: 120,
               custom_periods: [
                 { start_time: '18:00', end_time: '21:00', interval_minutes: 30 },
                 { start_time: '21:30', end_time: '23:00', interval_minutes: 30 }
               ])
      end

      it 'includes the special date in available dates API response' do
        # Test the main API flow through RestaurantAvailabilityService
        availability_service = RestaurantAvailabilityService.new(restaurant)
        available_dates = availability_service.get_available_dates(2) # party size 2

        expect(available_dates).to include(special_date.to_s)
      end

      it 'has_availability_on_date_cached? returns true for special dates' do
        # Test the specific method that was broken
        day_reservations = []
        restaurant_tables = restaurant.restaurant_tables.active.available_for_booking.includes(:table_group).to_a
        reservation_periods_cache = restaurant.reservation_periods.active.index_by(&:id)

        result = service.has_availability_on_date_cached?(
          special_date,
          day_reservations,
          restaurant_tables,
          reservation_periods_cache,
          2
        )

        expect(result).to be true
      end

      it 'restaurant.available_time_options_for_date returns time slots for special date' do
        time_options = restaurant.available_time_options_for_date(special_date)

        expect(time_options).not_to be_empty
        expect(time_options.map { |opt| opt[:time] }).to include('18:00', '18:30', '19:00', '21:30', '22:00')

        # Special dates should have nil reservation_period_id
        expect(time_options.all? { |opt| opt[:reservation_period_id].nil? }).to be true
      end
    end

    context 'when special date is closed' do
      let!(:special_reservation_date) do
        create(:special_reservation_date,
               restaurant: restaurant,
               start_date: special_date,
               end_date: special_date,
               operation_mode: 'closed')
      end

      it 'excludes the closed special date from available dates' do
        availability_service = RestaurantAvailabilityService.new(restaurant)
        available_dates = availability_service.get_available_dates(2)

        expect(available_dates).not_to include(special_date.to_s)
      end

      it 'restaurant.available_time_options_for_date returns empty for closed special date' do
        time_options = restaurant.available_time_options_for_date(special_date)

        expect(time_options).to be_empty
      end
    end

    context 'integration test with actual API call flow' do
      let!(:special_reservation_date) do
        create(:special_reservation_date,
               restaurant: restaurant,
               start_date: special_date,
               end_date: special_date,
               operation_mode: 'custom_hours',
               table_usage_minutes: 120,
               custom_periods: [
                 { start_time: '12:00', end_time: '14:00', interval_minutes: 30 }
               ])
      end

      it 'special date appears in RestaurantsController available_dates API' do
        # Simulate the controller logic
        party_size = 2
        availability_service = RestaurantAvailabilityService.new(restaurant)
        has_capacity = restaurant.has_capacity_for_party_size?(party_size)

        available_dates = if has_capacity
                            availability_service.get_available_dates(party_size, party_size, 0)
                          else
                            []
                          end

        expect(has_capacity).to be true
        expect(available_dates).to include(special_date.to_s)
      end
    end
  end
end
