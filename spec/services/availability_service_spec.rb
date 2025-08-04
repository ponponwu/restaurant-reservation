require 'rails_helper'

RSpec.describe AvailabilityService, type: :service do
  let(:restaurant) { create(:restaurant) }
  let(:service) { described_class.new(restaurant) }
  let(:lunch_period) { create(:reservation_period, restaurant: restaurant, name: '午餐', start_time: '11:30', end_time: '14:00') }
  let(:dinner_period) { create(:reservation_period, restaurant: restaurant, name: '晚餐', start_time: '17:30', end_time: '21:00') }
  let(:table_group) { create(:table_group, restaurant: restaurant, name: '主用餐區') }
  let!(:table_2) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 2, max_capacity: 2, table_number: 'A1') }
  let!(:table_4) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, max_capacity: 4, table_number: 'A2') }
  let!(:table_6) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 6, max_capacity: 6, table_number: 'A3') }

  before do
    lunch_period
    dinner_period
    restaurant.reload
  end

  describe '#has_any_availability_on_date?' do
    let(:test_date) { Date.current + 1.day }

    before do
      # Mock restaurant methods to return available time options
      allow(restaurant).to receive(:available_time_options_for_date).with(test_date).and_return([
                                                                                                  { datetime: test_date.beginning_of_day + 12.hours, reservation_period_id: lunch_period.id, time: '12:00' },
                                                                                                  { datetime: test_date.beginning_of_day + 18.hours, reservation_period_id: dinner_period.id, time: '18:00' }
                                                                                                ])
    end

    context '基本可用性測試' do
      it '當有可用桌位時返回 true' do
        expect(service.has_any_availability_on_date?(test_date, 2)).to be true
      end

      it '對大桌也返回 true' do
        expect(service.has_any_availability_on_date?(test_date, 4)).to be true
      end

      it '當人數超過所有桌位容量時返回 false' do
        expect(service.has_any_availability_on_date?(test_date, 10)).to be false
      end

      it '當沒有營業時段時返回 false' do
        allow(restaurant).to receive(:available_time_options_for_date).and_return([])
        expect(service.has_any_availability_on_date?(test_date, 2)).to be false
      end
    end

    context '桌位被預訂的情況' do
      before do
        # 預訂所有桌位的午餐時段
        create(:reservation,
               restaurant: restaurant,
               reservation_period: lunch_period,
               table: table_2,
               reservation_datetime: test_date.beginning_of_day + 12.hours,
               status: 'confirmed')
        create(:reservation,
               restaurant: restaurant,
               reservation_period: lunch_period,
               table: table_4,
               reservation_datetime: test_date.beginning_of_day + 12.hours,
               status: 'confirmed')
        create(:reservation,
               restaurant: restaurant,
               reservation_period: lunch_period,
               table: table_6,
               reservation_datetime: test_date.beginning_of_day + 12.hours,
               status: 'confirmed')
      end

      it '當只有午餐時段且全被預訂時返回 false' do
        allow(restaurant).to receive(:available_time_options_for_date).and_return([
                                                                                    { datetime: test_date.beginning_of_day + 12.hours, reservation_period_id: lunch_period.id, time: '12:00' }
                                                                                  ])

        expect(service.has_any_availability_on_date?(test_date, 2)).to be false
      end

      it '但晚餐時段仍可用時返回 true' do
        allow(restaurant).to receive(:available_time_options_for_date).and_return([
                                                                                    { datetime: test_date.beginning_of_day + 12.hours, reservation_period_id: lunch_period.id, time: '12:00' },
                                                                                    { datetime: test_date.beginning_of_day + 18.hours, reservation_period_id: dinner_period.id, time: '18:00' }
                                                                                  ])

        expect(service.has_any_availability_on_date?(test_date, 2)).to be true
      end
    end
  end

  describe '#get_available_slots_by_period' do
    let(:test_date) { Date.current + 1.day }
    let(:party_size) { 2 }
    let(:adults) { 2 }
    let(:children) { 0 }

    before do
      allow(restaurant).to receive(:available_time_options_for_date).and_return([
                                                                                  { datetime: test_date.beginning_of_day + 12.hours, reservation_period_id: lunch_period.id, time: '12:00' },
                                                                                  { datetime: test_date.beginning_of_day + 13.hours, reservation_period_id: lunch_period.id, time: '13:00' },
                                                                                  { datetime: test_date.beginning_of_day + 18.hours, reservation_period_id: dinner_period.id, time: '18:00' },
                                                                                  { datetime: test_date.beginning_of_day + 19.hours, reservation_period_id: dinner_period.id, time: '19:00' }
                                                                                ])
    end

    context '可用時段測試' do
      it '返回可用的時段' do
        slots = service.get_available_slots_by_period(test_date, party_size, adults, children)

        expect(slots).not_to be_empty
        expect(slots.first).to include(:time, :period_id, :period_name, :available)
      end

      it '包含正確的餐期資訊' do
        slots = service.get_available_slots_by_period(test_date, party_size, adults, children)

        lunch_slots = slots.select { |slot| slot[:period_id] == lunch_period.id }
        dinner_slots = slots.select { |slot| slot[:period_id] == dinner_period.id }

        expect(lunch_slots).not_to be_empty
        expect(dinner_slots).not_to be_empty
      end
    end

    context '有兒童的情況' do
      let(:children) { 1 }
      let!(:bar_table) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 2, max_capacity: 2, table_number: 'B1', table_type: 'bar') }

      it '排除吧台座位' do
        slots = service.get_available_slots_by_period(test_date, party_size, adults, children)
        expect(slots).not_to be_empty
      end
    end

    context '部分時段被預訂' do
      before do
        create(:reservation,
               restaurant: restaurant,
               reservation_period: lunch_period,
               table: table_2,
               reservation_datetime: test_date.beginning_of_day + 12.hours,
               status: 'confirmed')
        create(:reservation,
               restaurant: restaurant,
               reservation_period: lunch_period,
               table: table_4,
               reservation_datetime: test_date.beginning_of_day + 12.hours,
               status: 'confirmed')
        create(:reservation,
               restaurant: restaurant,
               reservation_period: lunch_period,
               table: table_6,
               reservation_datetime: test_date.beginning_of_day + 12.hours,
               status: 'confirmed')
      end

      it '只返回可用的時段' do
        slots = service.get_available_slots_by_period(test_date, party_size, adults, children)
        available_slots = slots.select { |slot| slot[:available] }
        expect(available_slots).not_to be_empty
      end
    end

    context '所有時段都被預訂' do
      before do
        [12, 13, 18, 19].each do |hour|
          period = hour < 15 ? lunch_period : dinner_period
          [table_2, table_4, table_6].each do |table|
            create(:reservation,
                   restaurant: restaurant,
                   reservation_period: period,
                   table: table,
                   reservation_datetime: test_date.beginning_of_day + hour.hours,
                   status: 'confirmed')
          end
        end
      end

      it '返回空陣列' do
        slots = service.get_available_slots_by_period(test_date, party_size, adults, children)
        expect(slots).to be_empty
      end
    end
  end

  describe '#check_availability_for_date_range' do
    let(:start_date) { Date.current + 1.day }
    let(:end_date) { Date.current + 7.days }
    let(:party_size) { 2 }

    context '所有日期都可用' do
      it '返回空陣列' do
        allow(restaurant).to receive(:available_time_options_for_date) do |date|
          [
            { datetime: date.beginning_of_day + 12.hours, reservation_period_id: lunch_period.id, time: '12:00' },
            { datetime: date.beginning_of_day + 18.hours, reservation_period_id: dinner_period.id, time: '18:00' }
          ]
        end

        unavailable_dates = service.check_availability_for_date_range(start_date, end_date, party_size)
        expect(unavailable_dates).to be_empty
      end
    end

    context '有休息日' do
      let!(:closure_date) { create(:closure_date, restaurant: restaurant, date: start_date + 2.days, reason: '公休') }

      it '正確處理休息日' do
        expect { service.check_availability_for_date_range(start_date, end_date, party_size) }.not_to raise_error

        unavailable_dates = service.check_availability_for_date_range(start_date, end_date, party_size)
        expect(unavailable_dates).to be_an(Array)
      end
    end

    context '某些日期完全被預訂' do
      before do
        test_date = start_date + 1.day

        [lunch_period, dinner_period].each do |period|
          [table_2, table_4, table_6].each do |table|
            create(:reservation,
                   restaurant: restaurant,
                   reservation_period: period,
                   table: table,
                   reservation_datetime: test_date.beginning_of_day + (period == lunch_period ? 12 : 18).hours,
                   status: 'confirmed')
          end
        end
      end

      it '包含完全被預訂的日期' do
        allow(restaurant).to receive(:available_time_options_for_date) do |date|
          [
            { datetime: date.beginning_of_day + 12.hours, reservation_period_id: lunch_period.id, time: '12:00' },
            { datetime: date.beginning_of_day + 18.hours, reservation_period_id: dinner_period.id, time: '18:00' }
          ]
        end

        unavailable_dates = service.check_availability_for_date_range(start_date, end_date, party_size)
        expect(unavailable_dates).to include((start_date + 1.day).to_s)
      end
    end
  end

  describe '#get_unavailable_dates_optimized' do
    let(:party_size) { 4 }
    let(:max_days) { 30 }

    context '有足夠桌位' do
      it '返回空陣列或少量不可用日期' do
        allow(restaurant).to receive(:available_time_options_for_date) do |date|
          [
            { datetime: date.beginning_of_day + 12.hours, reservation_period_id: lunch_period.id, time: '12:00' },
            { datetime: date.beginning_of_day + 18.hours, reservation_period_id: dinner_period.id, time: '18:00' }
          ]
        end

        unavailable_dates = service.get_unavailable_dates_optimized(party_size, max_days)
        expect(unavailable_dates).to be_empty
      end
    end

    context '桌位容量不足' do
      let(:party_size) { 10 }

      it '返回大量不可用日期' do
        unavailable_dates = service.get_unavailable_dates_optimized(party_size, max_days)
        expect(unavailable_dates.length).to be > 0
      end
    end

    context '效能測試' do
      it '在合理時間內完成' do
        start_time = Time.current
        service.get_unavailable_dates_optimized(party_size, max_days)
        end_time = Time.current
        execution_time = end_time - start_time

        expect(execution_time).to be < 1.0
      end
    end
  end

  describe 'private methods' do
    describe '#has_availability_for_slot?' do
      let(:test_datetime) { (Date.current + 1.day).beginning_of_day + 12.hours }
      let(:party_size) { 2 }
      let(:restaurant_tables) { [table_2, table_4] }

      it '當有可用桌位時返回 true' do
        result = service.send(:has_availability_for_slot?,
                              restaurant_tables,
                              [],
                              test_datetime,
                              party_size,
                              lunch_period.id)

        expect(result).to be true
      end

      it '當所有桌位都被預訂時返回 false' do
        future_datetime = (Date.current + 2.days).beginning_of_day + 12.hours
        reservations = [
          create(:reservation,
                 restaurant: restaurant,
                 reservation_period: lunch_period,
                 table: table_2,
                 reservation_datetime: future_datetime,
                 status: 'confirmed'),
          create(:reservation,
                 restaurant: restaurant,
                 reservation_period: lunch_period,
                 table: table_4,
                 reservation_datetime: future_datetime,
                 status: 'confirmed')
        ]

        result = service.send(:has_availability_for_slot?,
                              restaurant_tables,
                              reservations,
                              future_datetime,
                              party_size,
                              lunch_period.id)

        expect(result).to be false
      end

      it '當部分桌位被預訂但仍有適合桌位時返回 true' do
        future_datetime = (Date.current + 2.days).beginning_of_day + 12.hours
        reservations = [
          create(:reservation,
                 restaurant: restaurant,
                 reservation_period: lunch_period,
                 table: table_2,
                 reservation_datetime: future_datetime,
                 status: 'confirmed')
        ]

        result = service.send(:has_availability_for_slot?,
                              [table_2, table_4],
                              reservations,
                              future_datetime,
                              4,
                              lunch_period.id)

        expect(result).to be true
      end
    end

    describe '#build_closed_dates_cache' do
      let(:date_range) { [Date.current + 1.day, Date.current + 2.days, Date.current + 3.days] }
      let(:closure_dates) { [create(:closure_date, restaurant: restaurant, date: Date.current + 2.days)] }

      it '建立正確的休息日快取' do
        cache = service.send(:build_closed_dates_cache, closure_dates, date_range)

        expect(cache).to include(Date.current + 2.days)
        expect(cache).not_to include(Date.current + 1.day)
        expect(cache).not_to include(Date.current + 3.days)
      end
    end
  end

  describe '錯誤處理' do
    context '餐廳沒有桌位' do
      it '正確處理空桌位情況' do
        empty_restaurant = create(:restaurant)
        empty_service = described_class.new(empty_restaurant)

        expect { empty_service.has_any_availability_on_date?(Date.current + 1.day, 2) }.not_to raise_error
        expect(empty_service.has_any_availability_on_date?(Date.current + 1.day, 2)).to be false
      end
    end

    context '餐廳沒有營業時段' do
      it '正確處理空營業時段情況' do
        empty_restaurant = create(:restaurant)
        empty_service = described_class.new(empty_restaurant)

        expect { empty_service.has_any_availability_on_date?(Date.current + 1.day, 2) }.not_to raise_error
        expect(empty_service.has_any_availability_on_date?(Date.current + 1.day, 2)).to be false
      end
    end

    context '輸入無效參數' do
      it '處理負數人數' do
        expect { service.has_any_availability_on_date?(Date.current + 1.day, -1) }.not_to raise_error
        expect(service.has_any_availability_on_date?(Date.current + 1.day, -1)).to be false
      end

      it '處理零人數' do
        expect { service.has_any_availability_on_date?(Date.current + 1.day, 0) }.not_to raise_error
        expect(service.has_any_availability_on_date?(Date.current + 1.day, 0)).to be false
      end

      it '處理過去的日期' do
        past_date = Date.current - 1.day
        expect { service.has_any_availability_on_date?(past_date, 2) }.not_to raise_error
      end
    end
  end

  describe '快取機制' do
    it '避免重複計算已預訂桌位' do
      test_datetime = (Date.current + 1.day).beginning_of_day + 12.hours

      expect { service.send(:get_reserved_table_ids_for_period_optimized, [], test_datetime, lunch_period.id) }.not_to raise_error
    end

    it '正確清除快取' do
      service.instance_variable_set(:@reserved_table_ids_cache, { 'test' => [1, 2, 3] })

      new_service = described_class.new(restaurant)
      expect(new_service.instance_variable_get(:@reserved_table_ids_cache)).to eq({})
    end
  end
end
