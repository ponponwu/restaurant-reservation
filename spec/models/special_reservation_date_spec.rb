require 'rails_helper'

RSpec.describe SpecialReservationDate, type: :model do
  let(:restaurant) { create(:restaurant) }
  subject { build(:special_reservation_date, restaurant: restaurant) }

  # 1. 關聯測試
  describe 'associations' do
    it { is_expected.to belong_to(:restaurant) }
  end

  # 2. 驗證測試
  describe 'validations' do
    describe 'basic validations' do
      it { is_expected.to validate_presence_of(:name) }
      it { is_expected.to validate_length_of(:name).is_at_most(100) }
      it { is_expected.to validate_length_of(:description).is_at_most(500) }
      it { is_expected.to validate_presence_of(:start_date) }
      it { is_expected.to validate_presence_of(:end_date) }
      it 'validates operation_mode inclusion' do
        expect(subject).to allow_value('closed').for(:operation_mode)
        expect(subject).to allow_value('custom_hours').for(:operation_mode)
        
        # Test that invalid operation_mode raises an error
        expect { subject.operation_mode = 'invalid_mode' }.to raise_error(ArgumentError, /'invalid_mode' is not a valid operation_mode/)
      end
    end

    describe 'table_usage_minutes validation' do
      context 'when operation_mode is custom_hours' do
        subject { build(:special_reservation_date, :custom_hours, restaurant: restaurant) }
        
        it { is_expected.to validate_presence_of(:table_usage_minutes) }
        it { is_expected.to validate_numericality_of(:table_usage_minutes).is_greater_than(0) }
      end

      context 'when operation_mode is closed' do
        subject { build(:special_reservation_date, :closed, restaurant: restaurant) }
        
        it { is_expected.not_to validate_presence_of(:table_usage_minutes) }
      end
    end

    describe 'date validations' do
      it 'validates end_date is after start_date' do
        special_date = build(:special_reservation_date, 
                           restaurant: restaurant,
                           start_date: Date.current + 2.days,
                           end_date: Date.current + 1.day)
        
        expect(special_date).not_to be_valid
        expect(special_date.errors[:end_date]).to include('結束日期不能早於開始日期')
      end

      it 'validates start_date is not in the past' do
        special_date = build(:special_reservation_date,
                           restaurant: restaurant,
                           start_date: Date.current - 1.day,
                           end_date: Date.current + 1.day)
        
        expect(special_date).not_to be_valid
        expect(special_date.errors[:start_date]).to include('開始日期不能是過去的日期')
      end

      it 'allows start_date to be today' do
        special_date = build(:special_reservation_date,
                           restaurant: restaurant,
                           start_date: Date.current,
                           end_date: Date.current)
        
        expect(special_date).to be_valid
      end
    end

    describe 'date range overlap validation' do
      let!(:existing_special_date) do
        create(:special_reservation_date,
               restaurant: restaurant,
               start_date: Date.current + 5.days,
               end_date: Date.current + 7.days)
      end

      it 'prevents overlapping date ranges' do
        overlapping_date = build(:special_reservation_date,
                                restaurant: restaurant,
                                start_date: Date.current + 6.days,
                                end_date: Date.current + 8.days)
        
        expect(overlapping_date).not_to be_valid
        expect(overlapping_date.errors[:base]).to include(match(/日期範圍與現有特殊訂位日重疊/))
      end

      it 'allows non-overlapping date ranges' do
        non_overlapping_date = build(:special_reservation_date,
                                    restaurant: restaurant,
                                    start_date: Date.current + 10.days,
                                    end_date: Date.current + 12.days)
        
        expect(non_overlapping_date).to be_valid
      end

      it 'allows overlapping dates for different restaurants' do
        other_restaurant = create(:restaurant)
        overlapping_date = build(:special_reservation_date,
                                restaurant: other_restaurant,
                                start_date: Date.current + 6.days,
                                end_date: Date.current + 8.days)
        
        expect(overlapping_date).to be_valid
      end

      it 'ignores inactive special dates in overlap validation' do
        existing_special_date.update!(active: false)
        
        overlapping_date = build(:special_reservation_date,
                                restaurant: restaurant,
                                start_date: Date.current + 6.days,
                                end_date: Date.current + 8.days)
        
        expect(overlapping_date).to be_valid
      end
    end

    describe 'custom_periods validation' do
      it 'validates custom_periods format for custom_hours mode' do
        special_date = build(:special_reservation_date,
                           restaurant: restaurant,
                           operation_mode: 'custom_hours',
                           table_usage_minutes: 120,
                           custom_periods: 'invalid_format')
        
        expect(special_date).not_to be_valid
        expect(special_date.errors[:custom_periods]).to include('自訂時段格式錯誤')
      end

      it 'validates required fields in custom_periods' do
        special_date = build(:special_reservation_date,
                           restaurant: restaurant,
                           operation_mode: 'custom_hours',
                           table_usage_minutes: 120,
                           custom_periods: [{ start_time: '18:00' }])
        
        expect(special_date).not_to be_valid
        expect(special_date.errors[:custom_periods]).to include('時段 1 缺少 end_time')
        expect(special_date.errors[:custom_periods]).to include('時段 1 缺少 interval_minutes')
      end

      it 'validates interval_minutes is in allowed options' do
        special_date = build(:special_reservation_date,
                           restaurant: restaurant,
                           operation_mode: 'custom_hours',
                           table_usage_minutes: 120,
                           custom_periods: [{
                             start_time: '18:00',
                             end_time: '20:00',
                             interval_minutes: 45
                           }])
        
        expect(special_date).not_to be_valid
        expect(special_date.errors[:custom_periods]).to include(match(/間隔時間必須是.*分鐘之一/))
      end

      it 'validates end_time is after start_time in periods' do
        special_date = build(:special_reservation_date,
                           restaurant: restaurant,
                           operation_mode: 'custom_hours',
                           table_usage_minutes: 120,
                           custom_periods: [{
                             start_time: '20:00',
                             end_time: '18:00',
                             interval_minutes: 60
                           }])
        
        expect(special_date).not_to be_valid
        expect(special_date.errors[:custom_periods]).to include('時段 1 的結束時間必須晚於開始時間')
      end

      it 'validates time format in periods' do
        special_date = build(:special_reservation_date,
                           restaurant: restaurant,
                           operation_mode: 'custom_hours',
                           table_usage_minutes: 120,
                           custom_periods: [{
                             start_time: 'invalid_time',
                             end_time: '20:00',
                             interval_minutes: 60
                           }])
        
        expect(special_date).not_to be_valid
        expect(special_date.errors[:custom_periods]).to include('時段 1 的時間格式錯誤')
      end
    end
  end

  # 3. Scope 測試
  describe 'scopes' do
    let!(:active_special_date) { create(:special_reservation_date, restaurant: restaurant, active: true) }
    let!(:inactive_special_date) { create(:special_reservation_date, restaurant: restaurant, active: false) }

    describe '.active' do
      it 'returns only active special dates' do
        expect(SpecialReservationDate.active).to include(active_special_date)
        expect(SpecialReservationDate.active).not_to include(inactive_special_date)
      end
    end

    describe '.for_restaurant' do
      let(:other_restaurant) { create(:restaurant) }
      let!(:other_restaurant_special_date) { create(:special_reservation_date, restaurant: other_restaurant) }

      it 'returns special dates for specified restaurant' do
        results = SpecialReservationDate.for_restaurant(restaurant)
        expect(results).to include(active_special_date, inactive_special_date)
        expect(results).not_to include(other_restaurant_special_date)
      end
    end

    describe '.for_date' do
      let!(:current_special_date) do
        create(:special_reservation_date,
               restaurant: restaurant,
               start_date: Date.current,
               end_date: Date.current + 2.days)
      end
      let!(:future_special_date) do
        create(:special_reservation_date,
               restaurant: restaurant,
               start_date: Date.current + 10.days,
               end_date: Date.current + 12.days)
      end

      it 'returns special dates covering the specified date' do
        results = SpecialReservationDate.for_date(Date.current + 1.day)
        expect(results).to include(current_special_date)
        expect(results).not_to include(future_special_date)
      end
    end

    describe '.ordered_by_date' do
      let!(:older_date) { create(:special_reservation_date, restaurant: restaurant) }
      let!(:newer_date) { create(:special_reservation_date, restaurant: restaurant) }

      it 'orders by created_at desc (newest first)' do
        results = SpecialReservationDate.ordered_by_date
        expect(results.first).to eq(newer_date)
        expect(results.second).to eq(older_date)
      end
    end
  end

  # 4. Enum 測試
  describe 'enums' do
    it 'defines operation_mode enum' do
      expect(SpecialReservationDate.operation_modes).to eq({
        'closed' => 'closed',
        'custom_hours' => 'custom_hours'
      })
    end

    it 'provides query methods for operation_mode' do
      closed_date = create(:special_reservation_date, :closed, restaurant: restaurant)
      custom_hours_date = create(:special_reservation_date, :custom_hours, restaurant: restaurant)

      expect(closed_date.closed?).to be true
      expect(closed_date.custom_hours?).to be false
      expect(custom_hours_date.closed?).to be false
      expect(custom_hours_date.custom_hours?).to be true
    end
  end

  # 5. 實例方法測試
  describe 'instance methods' do
    describe '#display_name' do
      it 'returns the name' do
        special_date = build(:special_reservation_date, name: '測試特殊日', restaurant: restaurant)
        expect(special_date.display_name).to eq('測試特殊日')
      end
    end

    describe '#date_range' do
      it 'returns formatted date range' do
        special_date = build(:special_reservation_date,
                           restaurant: restaurant,
                           start_date: Date.new(2024, 1, 15),
                           end_date: Date.new(2024, 1, 17))
        
        expect(special_date.date_range).to eq('2024-01-15 ~ 2024-01-17')
      end
    end

    describe '#covers_date?' do
      let(:special_date) do
        create(:special_reservation_date,
               restaurant: restaurant,
               start_date: Date.current + 5.days,
               end_date: Date.current + 7.days)
      end

      it 'returns true for dates within range' do
        expect(special_date.covers_date?(Date.current + 6.days)).to be true
      end

      it 'returns false for dates outside range' do
        expect(special_date.covers_date?(Date.current + 4.days)).to be false
        expect(special_date.covers_date?(Date.current + 8.days)).to be false
      end

      it 'returns true for boundary dates' do
        expect(special_date.covers_date?(Date.current + 5.days)).to be true
        expect(special_date.covers_date?(Date.current + 7.days)).to be true
      end
    end

    describe '#duration_days' do
      it 'calculates duration in days' do
        special_date = build(:special_reservation_date,
                           restaurant: restaurant,
                           start_date: Date.current + 1.day,
                           end_date: Date.current + 3.days)
        
        expect(special_date.duration_days).to eq(3)
      end
    end

    describe '#generate_available_time_slots' do
      context 'when operation_mode is closed' do
        let(:special_date) { create(:special_reservation_date, :closed, restaurant: restaurant) }

        it 'returns empty array' do
          expect(special_date.generate_available_time_slots).to eq([])
        end
      end

      context 'when operation_mode is custom_hours' do
        let(:special_date) do
          create(:special_reservation_date,
                 restaurant: restaurant,
                 operation_mode: 'custom_hours',
                 table_usage_minutes: 120,
                 custom_periods: [{
                   start_time: '18:00',
                   end_time: '20:00',
                   interval_minutes: 120
                 }])
        end

        it 'generates time slots based on custom periods' do
          expected_slots = ['18:00', '20:00']
          expect(special_date.generate_available_time_slots).to eq(expected_slots)
        end
      end

      context 'with multiple periods' do
        let(:special_date) do
          create(:special_reservation_date,
                 restaurant: restaurant,
                 operation_mode: 'custom_hours',
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
          expected_slots = ['18:00', '19:00', '20:00', '21:00', '22:00', '23:00']
          expect(special_date.generate_available_time_slots).to eq(expected_slots)
        end
      end

      context 'with invalid interval' do
        let(:special_date) do
          build(:special_reservation_date,
                restaurant: restaurant,
                operation_mode: 'custom_hours',
                table_usage_minutes: 120,
                custom_periods: [{
                  start_time: '18:00',
                  end_time: '20:00',
                  interval_minutes: 45 # Invalid interval
                }])
        end

        it 'skips periods with invalid intervals' do
          # Skip validation to test the method behavior
          special_date.save(validate: false)
          expect(special_date.generate_available_time_slots).to eq([])
        end
      end
    end

    describe '#time_available?' do
      let(:special_date) do
        create(:special_reservation_date,
               restaurant: restaurant,
               operation_mode: 'custom_hours',
               table_usage_minutes: 120,
               custom_periods: [{
                 start_time: '18:00',
                 end_time: '20:00',
                 interval_minutes: 120
               }])
      end

      it 'returns true for available times' do
        expect(special_date.time_available?('18:00')).to be true
        expect(special_date.time_available?('20:00')).to be true
      end

      it 'returns false for unavailable times' do
        expect(special_date.time_available?('19:00')).to be false
        expect(special_date.time_available?('17:00')).to be false
      end

      context 'when operation_mode is closed' do
        let(:closed_special_date) { create(:special_reservation_date, :closed, restaurant: restaurant) }

        it 'returns false for all times' do
          expect(closed_special_date.time_available?('18:00')).to be false
        end
      end
    end
  end

  # 6. 回調函數測試
  describe 'callbacks' do
    describe 'before_validation :set_defaults' do
      it 'sets default values' do
        special_date = build(:special_reservation_date, 
                           restaurant: restaurant,
                           active: nil,
                           operation_mode: nil,
                           custom_periods: nil)
        
        special_date.valid?
        
        expect(special_date.active).to be true
        expect(special_date.operation_mode).to eq('closed')
        expect(special_date.custom_periods).to eq([])
      end
    end

    describe 'before_validation :sanitize_inputs' do
      it 'strips whitespace from name and description' do
        special_date = build(:special_reservation_date,
                           restaurant: restaurant,
                           name: '  測試名稱  ',
                           description: '  測試描述  ')
        
        special_date.valid?
        
        expect(special_date.name).to eq('測試名稱')
        expect(special_date.description).to eq('測試描述')
      end
    end
  end

  # 7. 整合測試
  describe 'integration scenarios' do
    context 'creating a special date with custom hours' do
      it 'successfully creates with valid custom periods' do
        special_date = build(:special_reservation_date,
                           restaurant: restaurant,
                           name: '新年特殊營業',
                           operation_mode: 'custom_hours',
                           table_usage_minutes: 180,
                           custom_periods: [
                             {
                               start_time: '17:00',
                               end_time: '21:00',
                               interval_minutes: 120
                             }
                           ])
        
        expect(special_date).to be_valid
        expect(special_date.save).to be true
        expect(special_date.generate_available_time_slots).to eq(['17:00', '19:00', '21:00'])
      end
    end

    context 'preventing overlapping dates' do
      let!(:existing_special_date) do
        create(:special_reservation_date,
               restaurant: restaurant,
               start_date: Date.current + 5.days,
               end_date: Date.current + 7.days)
      end

      it 'prevents creating overlapping special dates' do
        overlapping_date = build(:special_reservation_date,
                                restaurant: restaurant,
                                start_date: Date.current + 6.days,
                                end_date: Date.current + 8.days)
        
        expect(overlapping_date).not_to be_valid
        expect(overlapping_date.save).to be false
      end
    end
  end
end