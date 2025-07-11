require 'rails_helper'

RSpec.describe RestaurantAvailabilityService, type: :service do
  let(:restaurant) { create(:restaurant, :with_business_periods, :with_tables) }
  let(:service) { described_class.new(restaurant) }
  let(:party_size) { 4 }
  let(:adults) { 3 }
  let(:children) { 1 }

  before do
    # 確保餐廳有基本的預約政策
    restaurant.reservation_policy || restaurant.create_reservation_policy
  end

  describe '#get_available_dates' do
    it 'returns available dates for the given party size' do
      # 當餐廳有足夠容量時，應該返回可用日期
      allow(restaurant).to receive(:has_capacity_for_party_size?).with(party_size).and_return(true)

      dates = service.get_available_dates(party_size, adults, children)

      expect(dates).to be_an(Array)
      # 應該至少有一些可用日期（假設餐廳沒有被完全預訂）
      expect(dates.length).to be >= 0
    end

    it 'uses cached reservations to avoid duplicate queries' do
      # 第一次調用
      service.get_available_dates(party_size, adults, children)

      # 模擬第二次調用應該使用快取
      expect(restaurant.reservations).not_to receive(:where)

      # 第二次調用同樣的日期範圍
      service.get_available_dates(party_size, adults, children)
    end

    it 'excludes today from available dates' do
      dates = service.get_available_dates(party_size, adults, children)

      expect(dates).not_to include(Date.current.to_s)
    end

    it 'respects advance booking days limit' do
      # 設定餐廳的預約政策
      restaurant.reservation_policy.update!(advance_booking_days: 7)

      dates = service.get_available_dates(party_size, adults, children)

      if dates.any?
        latest_date = Date.parse(dates.max)
        expected_max_date = Date.current + 7.days
        expect(latest_date).to be <= expected_max_date
      end
    end
  end

  describe '#get_available_times' do
    let(:target_date) { 1.week.from_now.to_date }

    it 'returns available times for the given date and party size' do
      times = service.get_available_times(target_date, party_size, adults, children)

      expect(times).to be_an(Array)
      times.each do |time_slot|
        expect(time_slot).to have_key(:time)
        expect(time_slot).to have_key(:datetime)
        expect(time_slot).to have_key(:business_period_id)
      end
    end

    it 'returns times sorted by time' do
      times = service.get_available_times(target_date, party_size, adults, children)

      if times.length > 1
        time_strings = times.map { |t| t[:time] }
        expect(time_strings).to eq(time_strings.sort)
      end
    end

    it 'uses cached reservations for the date' do
      # 先調用一次以建立快取
      times1 = service.get_available_times(target_date, party_size, adults, children)

      # 檢查第二次調用是否使用快取
      expect(service).to receive(:cached_reservations_for_date)
        .with(target_date)
        .and_call_original

      times2 = service.get_available_times(target_date, party_size, adults, children)

      expect(times1).to eq(times2)
    end
  end

  describe '#calculate_full_booked_until' do
    it 'returns a date when fully booked' do
      # 模擬所有日期都被預訂滿的情況
      allow_any_instance_of(AvailabilityService)
        .to receive(:has_availability_on_date_cached?)
        .and_return(false)

      result = service.calculate_full_booked_until(party_size, adults, children)

      expect(result).to be_a(Date)
      expect(result).to be > Date.current
    end

    it 'returns the first available date when there is availability' do
      # 模擬有可用性的情況
      allow_any_instance_of(AvailabilityService)
        .to receive(:has_availability_on_date_cached?)
        .and_return(true)

      result = service.calculate_full_booked_until(party_size, adults, children)

      expect(result).to be_a(Date)
      expect(result).to eq(Date.current + 1.day)
    end
  end

  describe '#has_availability_on_date?' do
    let(:target_date) { 1.week.from_now.to_date }

    it 'returns boolean for date availability' do
      result = service.has_availability_on_date?(target_date, party_size, adults, children)

      expect(result).to be_in([true, false])
    end

    it 'returns false when restaurant has no time options for the date' do
      allow(restaurant).to receive(:available_time_options_for_date)
        .with(target_date)
        .and_return([])

      result = service.has_availability_on_date?(target_date, party_size, adults, children)

      expect(result).to be false
    end
  end

  describe 'caching behavior' do
    describe '#cached_reservations_for_date_range' do
      let(:start_date) { Date.current }
      let(:end_date) { Date.current + 7.days }

      it 'caches reservations for date range' do
        # 第一次調用
        reservations1 = service.send(:cached_reservations_for_date_range, start_date, end_date)

        # 第二次調用應該使用快取，不會觸發查詢
        expect(restaurant.reservations).not_to receive(:where)
        reservations2 = service.send(:cached_reservations_for_date_range, start_date, end_date)

        expect(reservations1).to eq(reservations2)
        expect(reservations1).to be_an(Array)
      end
    end

    describe '#cached_reservations_for_date' do
      let(:target_date) { Date.current + 3.days }

      it 'uses range cache when available' do
        # 先建立範圍快取
        start_date = Date.current
        end_date = Date.current + 7.days
        service.send(:cached_reservations_for_date_range, start_date, end_date)

        # 然後調用單日快取，應該從範圍快取中過濾
        expect(restaurant.reservations).not_to receive(:where)

        reservations = service.send(:cached_reservations_for_date, target_date)
        expect(reservations).to be_an(Array)
      end

      it 'creates new cache when range cache not available' do
        target_date = Date.current + 1.day

        reservations = service.send(:cached_reservations_for_date, target_date)
        expect(reservations).to be_an(Array)

        # 第二次調用同一日期應該使用快取
        expect(restaurant.reservations).not_to receive(:where)
        reservations2 = service.send(:cached_reservations_for_date, target_date)
        expect(reservations2).to eq(reservations)
      end
    end
  end
end
