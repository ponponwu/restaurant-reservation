require 'rails_helper'

RSpec.describe 'API Special Dates Integration', type: :request do
  let(:restaurant) { create(:restaurant) }
  let(:tomorrow) { Date.current + 1.day }
  let(:day_after_tomorrow) { Date.current + 2.days }

  before do
    # Create some basic business periods
    create(:reservation_period, restaurant: restaurant) # Default is lunch
    create(:reservation_period, :dinner, restaurant: restaurant)

    # Create table groups and tables
    table_group = create(:table_group, restaurant: restaurant)
    create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, max_capacity: 4)
    create(:table, restaurant: restaurant, table_group: table_group, capacity: 6, max_capacity: 6)
  end

  describe 'GET /restaurants/:slug/available_days' do
    context 'with special reservation dates' do
      let!(:special_closed_date) do
        create(:special_reservation_date, :closed,
               restaurant: restaurant,
               start_date: tomorrow,
               end_date: tomorrow)
      end

      let!(:special_custom_date) do
        create(:special_reservation_date, :custom_hours,
               restaurant: restaurant,
               start_date: day_after_tomorrow,
               end_date: day_after_tomorrow)
      end

      it 'excludes closed special dates from available days' do
        get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 2 }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['special_closures']).to include(tomorrow.to_s)
        expect(json_response['has_capacity']).to be true
      end

      it 'includes custom hours dates as available' do
        get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 2 }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        # Custom hours dates should not be in special_closures
        expect(json_response['special_closures']).not_to include(day_after_tomorrow.to_s)
      end
    end
  end

  describe 'GET /restaurants/:slug/available_dates' do
    context 'with special reservation dates' do
      let!(:special_custom_date) do
        create(:special_reservation_date, :custom_hours,
               restaurant: restaurant,
               start_date: tomorrow,
               end_date: tomorrow)
      end

      it 'includes dates with custom hours' do
        get "/restaurants/#{restaurant.slug}/available_dates", params: { party_size: 2 }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['available_dates']).to include(tomorrow.to_s)
        expect(json_response['has_capacity']).to be true
      end
    end

    context 'with closed special dates' do
      let!(:special_closed_date) do
        create(:special_reservation_date, :closed,
               restaurant: restaurant,
               start_date: tomorrow,
               end_date: tomorrow)
      end

      it 'excludes closed dates' do
        get "/restaurants/#{restaurant.slug}/available_dates", params: { party_size: 2 }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['available_dates']).not_to include(tomorrow.to_s)
      end
    end
  end

  describe 'GET /restaurants/:slug/available_times' do
    context 'with custom hours special date' do
      let!(:special_custom_date) do
        create(:special_reservation_date, :custom_hours,
               restaurant: restaurant,
               start_date: tomorrow,
               end_date: tomorrow)
      end

      it 'returns time slots based on custom hours' do
        get "/restaurants/#{restaurant.slug}/available_times",
            params: { date: tomorrow.to_s, party_size: 2 }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['available_times']).not_to be_empty

        # Should have time slots within the custom hours range (18:00-20:00 with 120min intervals)
        times = json_response['available_times'].map { |slot| slot['time'] }
        expect(times).to include('18:00')

        # Should not have times outside the custom range
        expect(times).not_to include('12:00') # Normal lunch time
        expect(times).not_to include('17:00') # Before custom start
        # Note: 20:00 might be included if it's at the exact end time boundary
      end
    end

    context 'with closed special date' do
      let!(:special_closed_date) do
        create(:special_reservation_date, :closed,
               restaurant: restaurant,
               start_date: tomorrow,
               end_date: tomorrow)
      end

      it 'returns empty times with closure message' do
        get "/restaurants/#{restaurant.slug}/available_times",
            params: { date: tomorrow.to_s, party_size: 2 }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['available_times']).to be_empty
        expect(json_response['message']).to eq('餐廳當天公休')
      end
    end

    context 'with normal business period date' do
      it 'returns normal time slots when no special date exists' do
        get "/restaurants/#{restaurant.slug}/available_times",
            params: { date: tomorrow.to_s, party_size: 2 }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['available_times']).not_to be_empty

        # Should include normal business period times
        times = json_response['available_times'].map { |slot| slot['time'] }
        expect(times.any? { |time| time.start_with?('12:') }).to be true # Lunch times
        expect(times.any? { |time| time.start_with?('18:') }).to be true # Dinner times
      end
    end
  end

  describe 'GET /restaurants/:slug/reservations/available_slots' do
    context 'with special custom hours date' do
      let!(:special_custom_date) do
        create(:special_reservation_date, :custom_hours,
               restaurant: restaurant,
               start_date: tomorrow,
               end_date: tomorrow)
      end

      it 'returns slots based on custom hours' do
        get "/restaurants/#{restaurant.slug}/reservations/available_slots",
            params: { date: tomorrow.to_s, adults: 2, children: 0 }

        if response.status != 200
          puts "Response status: #{response.status}"
          puts "Response body: #{response.body}"
        end

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['slots']).not_to be_empty

        # Should have slots within custom hours (18:00-20:00 with 120min intervals)
        times = json_response['slots'].map { |slot| slot['time'] }
        expect(times).to include('18:00')
      end
    end

    context 'with closed special date' do
      let!(:special_closed_date) do
        create(:special_reservation_date, :closed,
               restaurant: restaurant,
               start_date: tomorrow,
               end_date: tomorrow)
      end

      it 'returns empty slots with closure message' do
        get "/restaurants/#{restaurant.slug}/reservations/available_slots",
            params: { date: tomorrow.to_s, adults: 2, children: 0 }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['slots']).to be_empty
        expect(json_response['message']).to eq('餐廳當天公休')
      end
    end
  end
end
