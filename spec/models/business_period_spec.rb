require 'rails_helper'

RSpec.describe BusinessPeriod do
  include ActiveSupport::Testing::TimeHelpers
  # 1. 關聯測試
  describe 'associations' do
    it { is_expected.to belong_to(:restaurant) }
    it { is_expected.to have_many(:reservations).dependent(:nullify) }
    it { is_expected.to have_many(:reservation_slots).dependent(:destroy) }
  end

  # 2. 驗證測試
  describe 'validations' do
    let(:restaurant) { create(:restaurant) }
    
    subject { build(:business_period, restaurant: restaurant) }

    describe 'name' do
      it { is_expected.to validate_presence_of(:name) }
      it { is_expected.to validate_length_of(:name).is_at_most(100) }
    end

    describe 'display_name' do
      it { is_expected.to validate_length_of(:display_name).is_at_most(100) }
      
      it 'allows blank display_name' do
        subject.display_name = nil
        expect(subject).to be_valid
      end
    end

    describe 'time validations' do
      it { is_expected.to validate_presence_of(:start_time) }
      it { is_expected.to validate_presence_of(:end_time) }
      
      it 'validates end_time is after start_time' do
        subject.start_time = Time.zone.parse('14:00')
        subject.end_time = Time.zone.parse('12:00')
        expect(subject).not_to be_valid
        expect(subject.errors[:end_time]).to include('結束時間必須晚於開始時間')
      end

      it 'allows valid time range' do
        subject.start_time = Time.zone.parse('12:00')
        subject.end_time = Time.zone.parse('14:00')
        expect(subject).to be_valid
      end
    end

    describe 'days_of_week_mask' do
      it 'validates presence of days_of_week_mask' do
        subject.days_of_week_mask = 0
        expect(subject).not_to be_valid
        expect(subject.errors[:days_of_week_mask]).to include('必須大於0')
      end
      
      it { is_expected.to validate_numericality_of(:days_of_week_mask).is_greater_than(0) }
    end
  end

  # 3. Scope 測試
  describe 'scopes' do
    let(:restaurant) { create(:restaurant) }
    let!(:active_period) { create(:business_period, restaurant: restaurant, active: true) }
    let!(:inactive_period) { create(:business_period, restaurant: restaurant, active: false) }
    
    describe '.active' do
      it 'returns only active business periods' do
        expect(BusinessPeriod.active).to include(active_period)
        expect(BusinessPeriod.active).not_to include(inactive_period)
      end
    end

    describe '.inactive' do
      it 'returns only inactive business periods' do
        expect(BusinessPeriod.inactive).to include(inactive_period)
        expect(BusinessPeriod.inactive).not_to include(active_period)
      end
    end

    describe '.for_day' do
      let!(:monday_period) do
        create(:business_period, restaurant: restaurant, days_of_week: ['monday'])
      end
      let!(:tuesday_period) do
        create(:business_period, restaurant: restaurant, days_of_week: ['tuesday'])
      end

      it 'finds periods by symbol' do
        expect(BusinessPeriod.for_day(:monday)).to include(monday_period)
        expect(BusinessPeriod.for_day(:monday)).not_to include(tuesday_period)
      end

      it 'finds periods by string' do
        expect(BusinessPeriod.for_day('monday')).to include(monday_period)
        expect(BusinessPeriod.for_day('MONDAY')).to include(monday_period)
      end

      it 'finds periods by date' do
        monday_date = Date.current.beginning_of_week # Assuming Monday is beginning of week
        expect(BusinessPeriod.for_day(monday_date)).to include(monday_period)
      end
    end

    describe '.for_weekday' do
      let!(:sunday_period) do
        create(:business_period, restaurant: restaurant, days_of_week: ['sunday'])
      end
      let!(:monday_period) do
        create(:business_period, restaurant: restaurant, days_of_week: ['monday'])
      end

      it 'finds periods by weekday number (0-6)' do
        expect(BusinessPeriod.for_weekday(0)).to include(sunday_period) # Sunday = 0
        expect(BusinessPeriod.for_weekday(1)).to include(monday_period) # Monday = 1
      end

      it 'returns none for invalid weekday numbers' do
        expect(BusinessPeriod.for_weekday(7)).to be_empty
        expect(BusinessPeriod.for_weekday(-1)).to be_empty
      end
    end

    describe '.ordered' do
      let!(:late_period) { create(:business_period, restaurant: restaurant, start_time: '18:00', end_time: '22:00') }
      let!(:early_period) { create(:business_period, restaurant: restaurant, start_time: '12:00', end_time: '14:00') }

      it 'orders by start_time' do
        ordered_periods = BusinessPeriod.ordered
        expect(ordered_periods.first.start_time).to be < ordered_periods.last.start_time
      end
    end
  end

  # 4. 常數測試
  describe 'constants' do
    it 'defines DAYS_OF_WEEK with correct bitmask values' do
      expect(BusinessPeriod::DAYS_OF_WEEK[:monday]).to eq(1)
      expect(BusinessPeriod::DAYS_OF_WEEK[:tuesday]).to eq(2)
      expect(BusinessPeriod::DAYS_OF_WEEK[:wednesday]).to eq(4)
      expect(BusinessPeriod::DAYS_OF_WEEK[:thursday]).to eq(8)
      expect(BusinessPeriod::DAYS_OF_WEEK[:friday]).to eq(16)
      expect(BusinessPeriod::DAYS_OF_WEEK[:saturday]).to eq(32)
      expect(BusinessPeriod::DAYS_OF_WEEK[:sunday]).to eq(64)
    end

    it 'defines CHINESE_DAYS with correct translations' do
      expect(BusinessPeriod::CHINESE_DAYS[:monday]).to eq('星期一')
      expect(BusinessPeriod::CHINESE_DAYS[:sunday]).to eq('星期日')
    end
  end

  # 5. 類別方法測試
  describe 'class methods' do
    describe '.weekday_to_bit' do
      it 'converts weekday numbers to bitmask values' do
        expect(BusinessPeriod.weekday_to_bit(0)).to eq(64)  # Sunday
        expect(BusinessPeriod.weekday_to_bit(1)).to eq(1)   # Monday
        expect(BusinessPeriod.weekday_to_bit(2)).to eq(2)   # Tuesday
        expect(BusinessPeriod.weekday_to_bit(6)).to eq(32)  # Saturday
      end

      it 'returns nil for invalid weekday numbers' do
        expect(BusinessPeriod.weekday_to_bit(7)).to be_nil
        expect(BusinessPeriod.weekday_to_bit(-1)).to be_nil
        expect(BusinessPeriod.weekday_to_bit('invalid')).to be_nil
      end
    end

    describe '.bit_to_weekday' do
      it 'converts bitmask values to weekday numbers' do
        expect(BusinessPeriod.bit_to_weekday(64)).to eq(0)  # Sunday
        expect(BusinessPeriod.bit_to_weekday(1)).to eq(1)   # Monday
        expect(BusinessPeriod.bit_to_weekday(32)).to eq(6)  # Saturday
      end

      it 'returns nil for invalid bit values' do
        expect(BusinessPeriod.bit_to_weekday(0)).to be_nil
        expect(BusinessPeriod.bit_to_weekday(128)).to be_nil
      end
    end

    describe '.ransackable_attributes' do
      it 'returns allowed search attributes' do
        expected_attributes = %w[
          active created_at days_of_week_mask display_name end_time
          id name restaurant_id start_time updated_at
        ]
        expect(BusinessPeriod.ransackable_attributes).to match_array(expected_attributes)
      end
    end

    describe '.ransackable_associations' do
      it 'returns allowed search associations' do
        expected_associations = %w[restaurant reservations reservation_slots]
        expect(BusinessPeriod.ransackable_associations).to match_array(expected_associations)
      end
    end
  end

  # 6. Days of week 方法測試
  describe 'days of week methods' do
    let(:restaurant) { create(:restaurant) }
    
    describe '#days_of_week=' do
      let(:business_period) { build(:business_period, restaurant: restaurant) }

      it 'sets bitmask for single day' do
        business_period.days_of_week = ['monday']
        expect(business_period.days_of_week_mask).to eq(1)
      end

      it 'sets bitmask for multiple days' do
        business_period.days_of_week = ['monday', 'wednesday', 'friday']
        expect(business_period.days_of_week_mask).to eq(1 + 4 + 16) # 21
      end

      it 'handles empty array' do
        business_period.days_of_week = []
        expect(business_period.days_of_week_mask).to eq(0)
      end

      it 'handles nil input' do
        business_period.days_of_week = nil
        expect(business_period.days_of_week_mask).to eq(0)
      end
    end

    describe '#days_of_week' do
      let(:business_period) { create(:business_period, restaurant: restaurant, days_of_week_mask: 21) } # Mon, Wed, Fri

      it 'returns array of day strings' do
        expect(business_period.days_of_week).to match_array(['monday', 'wednesday', 'friday'])
      end

      it 'returns empty array for zero mask' do
        business_period.days_of_week_mask = 0
        expect(business_period.days_of_week).to eq([])
      end
    end

    describe '#operates_on_day?' do
      let(:business_period) { create(:business_period, restaurant: restaurant, days_of_week: ['monday', 'wednesday']) }

      it 'returns true for operating days' do
        expect(business_period.operates_on_day?(:monday)).to be true
        expect(business_period.operates_on_day?('monday')).to be true
        expect(business_period.operates_on_day?('MONDAY')).to be true
      end

      it 'returns false for non-operating days' do
        expect(business_period.operates_on_day?(:tuesday)).to be false
        expect(business_period.operates_on_day?('sunday')).to be false
      end

      it 'handles Date objects' do
        monday_date = Date.current.beginning_of_week # Assuming Monday is beginning of week
        tuesday_date = monday_date + 1.day
        
        expect(business_period.operates_on_day?(monday_date)).to be true
        expect(business_period.operates_on_day?(tuesday_date)).to be false
      end
    end

    describe '#operates_on_weekday?' do
      let(:business_period) { create(:business_period, restaurant: restaurant, days_of_week: ['sunday', 'monday']) }

      it 'returns true for operating weekdays' do
        expect(business_period.operates_on_weekday?(0)).to be true  # Sunday
        expect(business_period.operates_on_weekday?(1)).to be true  # Monday
      end

      it 'returns false for non-operating weekdays' do
        expect(business_period.operates_on_weekday?(2)).to be false # Tuesday
      end

      it 'returns false for invalid weekday numbers' do
        expect(business_period.operates_on_weekday?(7)).to be false
        expect(business_period.operates_on_weekday?(-1)).to be false
      end
    end

    describe '#chinese_days_of_week' do
      let(:business_period) { create(:business_period, restaurant: restaurant, days_of_week: ['monday', 'friday']) }

      it 'returns Chinese day names' do
        expect(business_period.chinese_days_of_week).to match_array(['星期一', '星期五'])
      end
    end

    describe '#formatted_days_of_week' do
      let(:business_period) { create(:business_period, restaurant: restaurant, days_of_week: ['monday', 'wednesday', 'friday']) }

      it 'returns formatted Chinese day names' do
        expect(business_period.formatted_days_of_week).to eq('星期一、星期三、星期五')
      end
    end
  end

  # 7. 實例方法測試
  describe 'instance methods' do
    let(:restaurant) { create(:restaurant) }
    let(:business_period) do
      create(:business_period,
             restaurant: restaurant,
             name: 'lunch',
             display_name: '午餐時段',
             start_time: '12:00',
             end_time: '14:00')
    end

    describe '#display_name_or_name' do
      it 'returns display_name when present' do
        expect(business_period.display_name_or_name).to eq('午餐時段')
      end

      it 'returns name when display_name is blank' do
        business_period.display_name = ''
        expect(business_period.display_name_or_name).to eq('lunch')
      end
    end

    describe '#full_display_name' do
      it 'returns display name with time range' do
        expect(business_period.full_display_name).to eq('午餐時段 (12:00 - 14:00)')
      end
    end

    describe '#display_with_time' do
      it 'returns display name with time range' do
        expect(business_period.display_with_time).to eq('午餐時段 (12:00 - 14:00)')
      end
    end

    describe '#formatted_time_range' do
      it 'returns formatted time range' do
        expect(business_period.formatted_time_range).to eq('12:00 - 14:00')
      end
    end

    describe '#duration_minutes' do
      it 'calculates duration in minutes' do
        expect(business_period.duration_minutes).to eq(120) # 2 hours
      end
    end

    describe '#available_on?' do
      let(:business_period) { create(:business_period, restaurant: restaurant, days_of_week: ['monday']) }

      it 'returns true for operating days' do
        expect(business_period.available_on?(:monday)).to be true
      end

      it 'returns false for non-operating days' do
        expect(business_period.available_on?(:tuesday)).to be false
      end
    end

    describe '#available_today?' do
      it 'delegates to available_on? with current date' do
        expect(business_period).to receive(:available_on?).with(Date.current).and_return(true)
        expect(business_period.available_today?).to be true
        
        expect(business_period).to receive(:available_on?).with(Date.current).and_return(false)
        expect(business_period.available_today?).to be false
      end

      it 'returns correct availability for specific dates' do
        business_period = create(:business_period, 
          restaurant: restaurant, 
          days_of_week: ['monday', 'wednesday', 'friday']
        )
        
        travel_to Date.new(2024, 1, 8) do  # Monday
          expect(business_period.available_today?).to be true
        end
        
        travel_to Date.new(2024, 1, 9) do  # Tuesday
          expect(business_period.available_today?).to be false
        end
        
        travel_to Date.new(2024, 1, 10) do  # Wednesday
          expect(business_period.available_today?).to be true
        end
      end
    end

    describe '#operates_on_date?' do
      it 'delegates to available_on?' do
        expect(business_period).to receive(:available_on?).with(Date.current)
        business_period.operates_on_date?(Date.current)
      end
    end

    describe '#current_reservations_count' do
      let!(:confirmed_reservation) do
        create(:reservation, :confirmed,
               business_period: business_period,
               reservation_datetime: 3.days.from_now.noon)
      end
      let!(:cancelled_reservation) do
        create(:reservation, :cancelled,
               business_period: business_period,
               reservation_datetime: 3.days.from_now.noon)
      end

      it 'counts only confirmed reservations for today' do
        # Update the test to use travel_to to simulate being on the reservation date
        travel_to 3.days.from_now do
          expect(business_period.current_reservations_count).to eq(1)
        end
      end
    end

    describe '#generate_time_slots' do
      it 'generates time slots with default 30-minute intervals' do
        slots = business_period.generate_time_slots
        expect(slots.length).to eq(4) # 12:00, 12:30, 13:00, 13:30
        expect(slots.first.strftime('%H:%M')).to eq('12:00')
        expect(slots.last.strftime('%H:%M')).to eq('13:30')
      end

      it 'generates time slots with custom intervals' do
        slots = business_period.generate_time_slots(60)
        expect(slots.length).to eq(2) # 12:00, 13:00
        expect(slots.map { |s| s.strftime('%H:%M') }).to eq(['12:00', '13:00'])
      end
    end

    describe 'settings methods' do
      describe '#settings' do
        it 'returns reservation_settings or empty hash' do
          business_period.reservation_settings = { 'max_capacity' => 50 }
          expect(business_period.settings).to eq({ 'max_capacity' => 50 })
        end

        it 'returns empty hash when reservation_settings is nil' do
          business_period.reservation_settings = nil
          expect(business_period.settings).to eq({})
        end
      end

      describe '#update_settings' do
        it 'merges new settings with existing ones' do
          business_period.reservation_settings = { 'max_capacity' => 50 }
          business_period.update_settings({ 'buffer_time' => 15 })
          
          expect(business_period.settings).to eq({
            'max_capacity' => 50,
            'buffer_time' => 15
          })
        end
      end
    end
  end

  # 8. 回調函數測試
  describe 'callbacks' do
    let(:restaurant) { create(:restaurant) }

    describe 'before_validation :set_defaults' do
      let(:business_period) { build(:business_period, restaurant: restaurant) }

      it 'sets default values' do
        business_period.days_of_week_mask = nil
        business_period.reservation_settings = nil
        business_period.active = nil
        
        business_period.valid?
        
        expect(business_period.days_of_week_mask).to eq(0)
        expect(business_period.reservation_settings).to eq({})
        expect(business_period.active).to be true
      end

      it 'sets display_name to name if blank' do
        business_period.name = 'lunch'
        business_period.display_name = nil
        
        business_period.valid?
        
        expect(business_period.display_name).to eq('lunch')
      end
    end

    describe 'before_validation :sanitize_inputs' do
      let(:business_period) { build(:business_period, restaurant: restaurant) }

      it 'strips whitespace from name and display_name' do
        business_period.name = '  lunch  '
        business_period.display_name = '  午餐時段  '
        
        business_period.valid?
        
        expect(business_period.name).to eq('lunch')
        expect(business_period.display_name).to eq('午餐時段')
      end
    end

    describe 'after_create :create_default_slots' do
      it 'creates default reservation slots after creation' do
        expect do
          create(:business_period, restaurant: restaurant, start_time: '12:00', end_time: '14:00')
        end.to change { ReservationSlot.count }.by(4) # 30-minute intervals
      end
    end
  end

  # 9. 整合測試
  describe 'integration scenarios' do
    let(:restaurant) { create(:restaurant) }

    context 'creating a complete business period' do
      it 'successfully creates with all attributes' do
        business_period_attrs = {
          restaurant: restaurant,
          name: 'dinner',
          display_name: '晚餐時段',
          start_time: '18:00',
          end_time: '22:00',
          days_of_week: ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'],
          active: true
        }

        expect do
          create(:business_period, business_period_attrs)
        end.to change(BusinessPeriod, :count).by(1)
      end

      it 'automatically creates reservation slots' do
        expect do
          create(:business_period,
                 restaurant: restaurant,
                 start_time: '18:00',
                 end_time: '20:00') # 2 hours = 4 slots
        end.to change(ReservationSlot, :count).by(4)
      end
    end

    context 'day-based querying workflow' do
      let!(:weekday_period) do
        create(:business_period,
               restaurant: restaurant,
               name: 'weekday_lunch',
               days_of_week: ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'])
      end
      let!(:weekend_period) do
        create(:business_period,
               restaurant: restaurant,
               name: 'weekend_brunch',
               days_of_week: ['saturday', 'sunday'])
      end

      it 'correctly identifies operating periods for specific days' do
        expect(BusinessPeriod.for_day(:monday)).to include(weekday_period)
        expect(BusinessPeriod.for_day(:monday)).not_to include(weekend_period)
        
        expect(BusinessPeriod.for_day(:saturday)).to include(weekend_period)
        expect(BusinessPeriod.for_day(:saturday)).not_to include(weekday_period)
      end

      it 'works with weekday numbers' do
        expect(BusinessPeriod.for_weekday(1)).to include(weekday_period) # Monday
        expect(BusinessPeriod.for_weekday(6)).to include(weekend_period) # Saturday
      end
    end
  end
end
