require 'rails_helper'

RSpec.describe 'Debug Special Reservation Date', type: :service do
  let(:restaurant) { create(:restaurant) }
  let(:table) { create(:table, restaurant: restaurant, capacity: 4) }
  let(:reservation_period) { create(:reservation_period, :dinner, restaurant: restaurant) }

  before do
    # Ensure business period is created
    reservation_period
    table
  end

  describe 'basic functionality' do
    it 'restaurant has business periods' do
      expect(restaurant.reservation_periods.active.count).to eq(1)
      expect(restaurant.reservation_periods.first.name).to eq('晚餐時段')
    end

    it 'normal business periods work' do
      # Test normal business periods first
      available_times = restaurant.available_time_options_for_date(Date.current + 1.day)
      puts "Available times: #{available_times.inspect}"
      expect(available_times).not_to be_empty
    end

    it 'special closed date works' do
      create(:special_reservation_date, :closed,
             restaurant: restaurant,
             start_date: Date.current + 1.day,
             end_date: Date.current + 1.day)

      available_times = restaurant.available_time_options_for_date(Date.current + 1.day)
      puts "Special date closed - available times: #{available_times.inspect}"
      expect(available_times).to be_empty
    end

    it 'special custom hours work' do
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

      available_times = restaurant.available_time_options_for_date(Date.current + 1.day)
      puts "Special date custom hours - available times: #{available_times.inspect}"
      expect(available_times.size).to eq(2)
      expect(available_times.map { |t| t[:time] }).to contain_exactly('18:00', '20:00')
    end
  end
end
