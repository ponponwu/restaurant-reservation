require 'rails_helper'

RSpec.describe Restaurant, type: :model do
  describe 'validations' do
    subject { build(:restaurant) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(100) }
    it { should validate_presence_of(:phone) }
    it { should validate_length_of(:phone).is_at_most(20) }
    it { should validate_presence_of(:address) }
    it { should validate_length_of(:address).is_at_most(255) }
    it { should validate_length_of(:description).is_at_most(1000) }
    it { should validate_presence_of(:reservation_interval_minutes) }
    it { should validate_inclusion_of(:reservation_interval_minutes).in_array([15, 30, 60]) }
    it { should validate_presence_of(:slug) }
    it { should validate_uniqueness_of(:slug) }

    context 'when reservation_interval_minutes is invalid' do
      it 'adds custom error message' do
        restaurant = build(:restaurant, reservation_interval_minutes: 45)
        expect(restaurant).not_to be_valid
        expect(restaurant.errors[:reservation_interval_minutes]).to include('預約間隔必須是 15、30 或 60 分鐘')
      end
    end
  end

  describe 'associations' do
    it { should have_many(:users).dependent(:nullify) }
    it { should have_many(:restaurant_tables).dependent(:destroy) }
    it { should have_many(:table_groups).dependent(:destroy) }
    it { should have_many(:business_periods).dependent(:destroy) }
    it { should have_many(:reservations).dependent(:destroy) }
    it { should have_many(:reservation_slots).through(:business_periods) }
    it { should have_many(:closure_dates).dependent(:destroy) }
    it { should have_one(:reservation_policy).dependent(:destroy) }
  end

  describe 'scopes' do
    let!(:active_restaurant) { create(:restaurant, active: true, deleted_at: nil) }
    let!(:inactive_restaurant) { create(:restaurant, active: false) }
    let!(:deleted_restaurant) { create(:restaurant, deleted_at: Time.current) }

    describe '.active' do
      it 'returns only active and non-deleted restaurants' do
        expect(Restaurant.active).to include(active_restaurant)
        expect(Restaurant.active).not_to include(inactive_restaurant)
        expect(Restaurant.active).not_to include(deleted_restaurant)
      end
    end

    describe '.search_by_name' do
      let!(:pizza_restaurant) { create(:restaurant, name: 'Pizza Palace') }
      let!(:burger_restaurant) { create(:restaurant, name: 'Burger King') }

      it 'returns restaurants matching the search term' do
        results = Restaurant.search_by_name('Pizza')
        expect(results).to include(pizza_restaurant)
        expect(results).not_to include(burger_restaurant)
      end

      it 'is case insensitive' do
        results = Restaurant.search_by_name('pizza')
        expect(results).to include(pizza_restaurant)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sanitizes inputs' do
        restaurant = build(:restaurant, name: '  Test Restaurant  ', phone: '  123-456-7890  ')
        restaurant.valid?
        expect(restaurant.name).to eq('Test Restaurant')
        expect(restaurant.phone).to eq('123-456-7890')
      end

      it 'generates slug when name changes' do
        restaurant = build(:restaurant, name: 'Test Restaurant')
        restaurant.valid?
        expect(restaurant.slug).to eq('test-restaurant')
      end
    end

    describe 'after_create' do
      it 'creates default reservation policy' do
        restaurant = create(:restaurant)
        expect(restaurant.reservation_policy).to be_present
      end
    end
  end

  describe 'instance methods' do
    let(:restaurant) { create(:restaurant) }

    describe '#soft_delete!' do
      it 'sets active to false and deleted_at to current time' do
        freeze_time do
          restaurant.soft_delete!
          expect(restaurant.active).to be false
          expect(restaurant.deleted_at).to eq(Time.current)
        end
      end
    end

    describe '#restore!' do
      it 'sets active to true and deleted_at to nil' do
        restaurant.update!(active: false, deleted_at: Time.current)
        restaurant.restore!
        expect(restaurant.active).to be true
        expect(restaurant.deleted_at).to be_nil
      end
    end

    describe '#calculate_total_capacity' do
      it 'returns 0 when no tables' do
        expect(restaurant.calculate_total_capacity).to eq(0)
      end

      it 'sums max_capacity of all tables' do
        create(:table, restaurant: restaurant, max_capacity: 4)
        create(:table, restaurant: restaurant, max_capacity: 6)
        expect(restaurant.calculate_total_capacity).to eq(10)
      end
    end

    describe '#total_capacity' do
      it 'returns cached value if present' do
        restaurant.update_column(:total_capacity, 20)
        expect(restaurant.total_capacity).to eq(20)
      end

      it 'calculates and caches capacity if not present' do
        create(:table, restaurant: restaurant, max_capacity: 8)
        expect(restaurant.total_capacity).to eq(8)
        expect(restaurant.reload.total_capacity).to eq(8)
      end
    end

    describe '#to_param' do
      it 'returns slug' do
        restaurant.update!(slug: 'test-restaurant')
        expect(restaurant.to_param).to eq('test-restaurant')
      end
    end

    describe '#has_capacity_for_party_size?' do
      context 'when no active tables' do
        it 'returns false' do
          expect(restaurant.has_capacity_for_party_size?(4)).to be false
        end
      end

      context 'when has suitable table' do
        before { create(:table, restaurant: restaurant, max_capacity: 6, operational_status: 'normal') }

        it 'returns true for party size within capacity' do
          expect(restaurant.has_capacity_for_party_size?(4)).to be true
        end

        it 'returns false for party size exceeding capacity' do
          expect(restaurant.has_capacity_for_party_size?(8)).to be false
        end
      end
    end

    describe '#closed_on_date?' do
      let(:date) { Date.current }

      context 'with specific date closure' do
        before { create(:closure_date, restaurant: restaurant, closure_date: date) }

        it 'returns true' do
          expect(restaurant.closed_on_date?(date)).to be true
        end
      end

      context 'with weekly recurring closure' do
        before do
          weekday = date.wday
          create(:closure_date, restaurant: restaurant, recurring: true, weekday: weekday)
        end

        it 'returns true' do
          expect(restaurant.closed_on_date?(date)).to be true
        end
      end

      context 'with no closures' do
        it 'returns false' do
          expect(restaurant.closed_on_date?(date)).to be false
        end
      end
    end

    describe '#formatted_business_hours' do
      let!(:business_period) do
        create(:business_period, 
               restaurant: restaurant,
               days_of_week: ['monday', 'tuesday'],
               start_time: '09:00',
               end_time: '17:00',
               status: :active)
      end

      it 'returns formatted hours for all weekdays' do
        hours = restaurant.formatted_business_hours
        expect(hours).to be_an(Array)
        expect(hours.size).to eq(7)
        
        # Monday should be open
        monday_hours = hours.find { |h| h[:day_of_week] == 1 }
        expect(monday_hours[:is_closed]).to be false
        expect(monday_hours[:periods]).not_to be_empty
        
        # Wednesday should be closed
        wednesday_hours = hours.find { |h| h[:day_of_week] == 3 }
        expect(wednesday_hours[:is_closed]).to be true
      end

      it 'handles recurring closures' do
        # Create a recurring closure for Monday
        create(:closure_date, restaurant: restaurant, recurring: true, weekday: 1)

        hours = restaurant.formatted_business_hours
        monday_hours = hours.find { |h| h[:day_of_week] == 1 }
        expect(monday_hours[:is_closed]).to be true
        expect(monday_hours[:periods]).to be_empty
      end

      it 'efficiently loads data without N+1 queries' do
        expect { restaurant.formatted_business_hours }.not_to exceed_query_limit(3)
      end
    end

    describe '#generate_time_slots_for_period' do
      include ActiveSupport::Testing::TimeHelpers
      
      let(:business_period) do
        create(:business_period, 
               restaurant: restaurant,
               start_time: '10:00',
               end_time: '16:00')
      end
      
      context 'with minimum_advance_hours setting' do
        before do
          # 設定餐廳政策
          policy = restaurant.reservation_policy || restaurant.create_reservation_policy
          policy.update!(minimum_advance_hours: 2)
        end
        
        it 'filters out time slots that are too close to current time' do
          # 使用今天的日期進行測試
          today = Date.current
          
          # 模擬當前時間為 11:00
          travel_to Time.zone.parse("#{today} 11:00") do
            slots = restaurant.generate_time_slots_for_period(business_period, today)
            
            # 應該過濾掉 11:XX 和 12:XX 的時間槽（2小時內）
            # 只保留 13:00 之後的時間槽
            slot_times = slots.map { |slot| slot[:time] }
            
            expect(slot_times).not_to include('11:00', '11:30', '12:00', '12:30')
            expect(slot_times).to include('13:00', '13:30', '14:00')
          end
        end
        
        it 'includes all slots when minimum_advance_hours is 0' do
          # 設定為無最小提前時間限制
          restaurant.reservation_policy.update!(minimum_advance_hours: 0)
          
          today = Date.current
          travel_to Time.zone.parse("#{today} 11:00") do
            slots = restaurant.generate_time_slots_for_period(business_period, today)
            
            # 應該包含所有未來的時間槽
            slot_times = slots.map { |slot| slot[:time] }
            expect(slot_times).to include('11:00', '11:30', '12:00', '12:30', '13:00')
          end
        end
      end
    end
  end

  describe 'slug generation' do
    it 'generates slug from name' do
      restaurant = create(:restaurant, name: 'Amazing Restaurant')
      expect(restaurant.slug).to eq('amazing-restaurant')
    end

    it 'ensures slug uniqueness' do
      create(:restaurant, name: 'Test Restaurant', slug: 'test-restaurant')
      restaurant2 = create(:restaurant, name: 'Test Restaurant')
      expect(restaurant2.slug).to eq('test-restaurant-1')
    end

    it 'generates fallback slug when name is blank' do
      restaurant = build(:restaurant, name: '')
      restaurant.save(validate: false)
      expect(restaurant.slug).to match(/restaurant-\d+/)
    end
  end
end
