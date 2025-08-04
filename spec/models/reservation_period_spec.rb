require 'rails_helper'

RSpec.describe ReservationPeriod do
  include ActiveSupport::Testing::TimeHelpers

  # 1. 關聯測試
  describe 'associations' do
    it { is_expected.to belong_to(:restaurant) }
    it { is_expected.to have_many(:reservations).dependent(:nullify) }
    it { is_expected.to have_many(:reservation_slots).dependent(:destroy) }
  end

  # 2. 驗證測試
  describe 'validations' do
    subject { build(:reservation_period, restaurant: restaurant) }

    let(:restaurant) { create(:restaurant) }

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

    describe 'weekday' do
      it { is_expected.to validate_presence_of(:weekday) }
      it { is_expected.to validate_inclusion_of(:weekday).in_range(0..6) }

      it 'allows valid weekday values' do
        (0..6).each do |weekday|
          subject.weekday = weekday
          expect(subject).to be_valid
        end
      end

      it 'does not allow invalid weekday values' do
        [-1, 7, 8].each do |invalid_weekday|
          subject.weekday = invalid_weekday
          expect(subject).not_to be_valid
        end
      end
    end

    describe 'reservation_interval_minutes' do
      it { is_expected.to validate_inclusion_of(:reservation_interval_minutes).in_array([15, 30, 60, 90, 120, 150, 180, 210, 240]) }

      it 'allows valid interval values' do
        [15, 30, 60, 90, 120, 150, 180, 210, 240].each do |interval|
          subject.reservation_interval_minutes = interval
          expect(subject).to be_valid
        end
      end

      it 'does not allow invalid interval values' do
        [5, 10, 45, 300].each do |invalid_interval|
          subject.reservation_interval_minutes = invalid_interval
          expect(subject).not_to be_valid
        end
      end
    end
  end

  # 3. (Enum 測試已移除，因為 operation_mode 已不存在)

  # 4. Scope 測試
  describe 'scopes' do
    let(:restaurant) { create(:restaurant) }
    let!(:active_period) { create(:reservation_period, restaurant: restaurant, active: true) }
    let!(:inactive_period) { create(:reservation_period, restaurant: restaurant, active: false) }
    let!(:monday_period) { create(:reservation_period, :monday, restaurant: restaurant) }
    let!(:tuesday_period) { create(:reservation_period, :tuesday, restaurant: restaurant) }
    let!(:weekend_period) { create(:reservation_period, :saturday, restaurant: restaurant) }
    let!(:specific_date_period) { create(:reservation_period, :specific_date, restaurant: restaurant) }

    describe '.active' do
      it 'returns only active periods' do
        expect(ReservationPeriod.active).to include(active_period)
        expect(ReservationPeriod.active).not_to include(inactive_period)
      end
    end

    describe '.inactive' do
      it 'returns only inactive periods' do
        expect(ReservationPeriod.inactive).to include(inactive_period)
        expect(ReservationPeriod.inactive).not_to include(active_period)
      end
    end

    describe '.for_weekday' do
      it 'returns periods for specific weekday' do
        expect(ReservationPeriod.for_weekday(1)).to include(monday_period)
        expect(ReservationPeriod.for_weekday(1)).not_to include(tuesday_period)
        expect(ReservationPeriod.for_weekday(2)).to include(tuesday_period)
        expect(ReservationPeriod.for_weekday(6)).to include(weekend_period)
      end
    end

    describe '.for_date' do
      it 'returns periods for specific date' do
        expect(ReservationPeriod.for_date(specific_date_period.date)).to include(specific_date_period)
        expect(ReservationPeriod.for_date(Date.current)).not_to include(specific_date_period)
      end
    end

    describe '.default_weekly' do
      it 'returns only default weekly periods (no specific date)' do
        expect(ReservationPeriod.default_weekly).to include(monday_period, tuesday_period, weekend_period)
        expect(ReservationPeriod.default_weekly).not_to include(specific_date_period)
      end
    end

    describe '.specific_date' do
      it 'returns only specific date periods' do
        expect(ReservationPeriod.specific_date).to include(specific_date_period)
        expect(ReservationPeriod.specific_date).not_to include(monday_period)
      end
    end

    describe '.ordered' do
      it 'returns periods ordered by start_time' do
        early_period = create(:reservation_period, restaurant: restaurant, start_time: '08:00', end_time: '10:00')
        late_period = create(:reservation_period, restaurant: restaurant, start_time: '20:00', end_time: '22:00')

        ordered_periods = ReservationPeriod.ordered
        expect(ordered_periods.index(early_period)).to be < ordered_periods.index(late_period)
      end
    end
  end

  # 5. 實例方法測試
  describe 'instance methods' do
    let(:restaurant) { create(:restaurant) }
    let(:reservation_period) { create(:reservation_period, :monday, restaurant: restaurant) }

    describe '#chinese_weekday' do
      it 'returns correct Chinese weekday names' do
        expect(create(:reservation_period, :sunday).chinese_weekday).to eq('星期日')
        expect(create(:reservation_period, :monday).chinese_weekday).to eq('星期一')
        expect(create(:reservation_period, :tuesday).chinese_weekday).to eq('星期二')
        expect(create(:reservation_period, :wednesday).chinese_weekday).to eq('星期三')
        expect(create(:reservation_period, :thursday).chinese_weekday).to eq('星期四')
        expect(create(:reservation_period, :friday).chinese_weekday).to eq('星期五')
        expect(create(:reservation_period, :saturday).chinese_weekday).to eq('星期六')
      end
    end

    describe '#operates_on_weekday?' do
      it 'returns true for matching weekday' do
        expect(reservation_period.operates_on_weekday?(1)).to be true
        expect(reservation_period.operates_on_weekday?(2)).to be false
      end
    end

    describe '#operates_on_date?' do
      let(:monday_date) { Date.current.beginning_of_week(:monday) } # 星期一
      let(:tuesday_date) { Date.current.beginning_of_week(:monday) + 1.day } # 星期二
      let(:specific_date) { Date.current + 5.days }

      context 'with default weekly period' do
        it 'returns true for matching weekday' do
          expect(reservation_period.operates_on_date?(monday_date)).to be true
          expect(reservation_period.operates_on_date?(tuesday_date)).to be false
        end
      end

      context 'with specific date period' do
        let(:specific_period) { create(:reservation_period, restaurant: restaurant, date: specific_date) }

        it 'returns true for matching specific date' do
          expect(specific_period.operates_on_date?(specific_date)).to be true
          expect(specific_period.operates_on_date?(monday_date)).to be false
        end
      end
    end

    describe '#specific_date?' do
      it 'returns true when date is set' do
        period_with_date = create(:reservation_period, :specific_date, restaurant: restaurant)
        expect(period_with_date.specific_date?).to be true
      end

      it 'returns false when date is not set' do
        expect(reservation_period.specific_date?).to be false
      end
    end

    describe '#default_weekly?' do
      it 'returns true when date is not set' do
        expect(reservation_period.default_weekly?).to be true
      end

      it 'returns false when date is set' do
        period_with_date = create(:reservation_period, :specific_date, restaurant: restaurant)
        expect(period_with_date.default_weekly?).to be false
      end
    end

    describe '#available_on?' do
      let(:monday_date) { Date.current.beginning_of_week(:monday) }
      let(:tuesday_date) { Date.current.beginning_of_week(:monday) + 1.day }

      it 'returns true for matching date' do
        expect(reservation_period.available_on?(monday_date)).to be true
        expect(reservation_period.available_on?(tuesday_date)).to be false
      end
    end

    describe '#available_today?' do
      it 'returns true when period operates on current day' do
        travel_to(Date.current.beginning_of_week(:monday)) do # 星期一
          expect(reservation_period.available_today?).to be true
        end
      end

      it 'returns false when period does not operate on current day' do
        travel_to(Date.current.beginning_of_week(:monday) + 1.day) do # 星期二
          expect(reservation_period.available_today?).to be false
        end
      end
    end

    describe '#display_name_or_name' do
      it 'returns display_name when present' do
        reservation_period.display_name = '顯示名稱'
        expect(reservation_period.display_name_or_name).to eq('顯示名稱')
      end

      it 'returns name when display_name is blank' do
        reservation_period.display_name = nil
        expect(reservation_period.display_name_or_name).to eq(reservation_period.name)
      end
    end

    describe '#duration_minutes' do
      it 'calculates duration correctly' do
        reservation_period.start_time = Time.zone.parse('12:00')
        reservation_period.end_time = Time.zone.parse('14:00')
        expect(reservation_period.duration_minutes).to eq(120)
      end
    end

    describe '#formatted_time_range' do
      it 'formats time range correctly' do
        reservation_period.start_time = Time.zone.parse('12:00')
        reservation_period.end_time = Time.zone.parse('14:00')
        expect(reservation_period.formatted_time_range).to eq('12:00 - 14:00')
      end
    end
  end

  # 6. 回調測試
  describe 'callbacks' do
    describe '#set_defaults' do
      it 'sets default values' do
        period = ReservationPeriod.new
        period.valid? # 觸發回調

        expect(period.active).to be true
        expect(period.reservation_interval_minutes).to eq(30)
      end
    end
  end

  # 7. Factory 測試
  describe 'factories' do
    it 'creates valid reservation period' do
      expect(create(:reservation_period)).to be_valid
    end

    it 'creates reservation period with traits' do
      expect(create(:reservation_period, :weekend)).to be_valid
      expect(create(:reservation_period, :dinner)).to be_valid
      expect(create(:reservation_period, :twenty_four_hours)).to be_valid
      expect(create(:reservation_period, :closed)).to be_valid
      expect(create(:reservation_period, :specific_date)).to be_valid
    end
  end
end
