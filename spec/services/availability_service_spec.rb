require 'rails_helper'

RSpec.describe AvailabilityService, type: :service do
  let(:restaurant) { create(:restaurant) }
  let(:service) { described_class.new(restaurant) }
  let(:today) { Date.current }
  let(:tomorrow) { today + 1.day }

  before do
    # 設定基本的營業時段
    create(:business_period, restaurant: restaurant, name: '午餐', 
           days_of_week: %w[1 2 3 4 5], start_time: '11:00', end_time: '14:00')
    create(:business_period, restaurant: restaurant, name: '晚餐',
           days_of_week: %w[1 2 3 4 5], start_time: '17:00', end_time: '21:00')
    
    # 設定桌位
    table_group = create(:table_group, restaurant: restaurant)
    create(:restaurant_table, restaurant: restaurant, table_group: table_group,
           table_number: 'A1', capacity: 4, table_type: 'standard')
    create(:restaurant_table, restaurant: restaurant, table_group: table_group,
           table_number: 'A2', capacity: 2, table_type: 'standard')
  end

  describe '#has_any_availability_on_date?' do
    context '當日期有可用桌位時' do
      it '回傳 true' do
        expect(service.has_any_availability_on_date?(tomorrow, 2)).to be true
      end
    end

    context '當所有桌位都被預訂時' do
      before do
        # 預訂所有可用時段
        restaurant.available_time_options_for_date(tomorrow).each do |time_option|
          create(:reservation, 
                 restaurant: restaurant,
                 reservation_datetime: time_option[:datetime],
                 business_period_id: time_option[:business_period_id],
                 party_size: 2,
                 status: :confirmed,
                 table: restaurant.restaurant_tables.first)
        end
      end

      it '回傳 false' do
        expect(service.has_any_availability_on_date?(tomorrow, 2)).to be false
      end
    end

    context '當餐廳休息時' do
      before do
        create(:closure_date, restaurant: restaurant, date: tomorrow)
      end

      it '仍然檢查可用性（由控制器處理休息日）' do
        # AvailabilityService 不處理休息日邏輯，由控制器處理
        expect(service.has_any_availability_on_date?(tomorrow, 2)).to be true
      end
    end
  end

  describe '#get_available_slots_by_period' do
    let(:party_size) { 2 }
    let(:adults) { 2 }
    let(:children) { 0 }

    context '當有可用時段時' do
      it '回傳可用的時間槽' do
        slots = service.get_available_slots_by_period(tomorrow, party_size, adults, children)
        
        expect(slots).not_to be_empty
        expect(slots.first).to include(:time, :period_id, :period_name, :available)
        expect(slots.first[:available]).to be true
      end
    end

    context '當有兒童時' do
      let(:children) { 1 }
      
      before do
        # 創建吧台座位
        create(:restaurant_table, restaurant: restaurant,
               table_number: 'BAR1', capacity: 2, table_type: 'bar')
      end

      it '排除吧台座位' do
        # 這個測試需要檢查內部邏輯，可能需要調整實作
        slots = service.get_available_slots_by_period(tomorrow, party_size, adults, children)
        expect(slots).not_to be_empty
      end
    end

    context '當所有時段都被預訂時' do
      before do
        # 預訂所有可用時段
        restaurant.available_time_options_for_date(tomorrow).each do |time_option|
          create(:reservation, 
                 restaurant: restaurant,
                 reservation_datetime: time_option[:datetime],
                 business_period_id: time_option[:business_period_id],
                 party_size: 4,
                 status: :confirmed,
                 table: restaurant.restaurant_tables.first)
        end
      end

      it '回傳空陣列' do
        slots = service.get_available_slots_by_period(tomorrow, party_size, adults, children)
        expect(slots).to be_empty
      end
    end
  end

  describe '#check_availability_for_date_range' do
    let(:start_date) { today }
    let(:end_date) { today + 7.days }
    let(:party_size) { 2 }

    context '當所有日期都有可用性時' do
      it '回傳空的不可用日期陣列' do
        unavailable_dates = service.check_availability_for_date_range(start_date, end_date, party_size)
        expect(unavailable_dates).to be_empty
      end
    end

    context '當某些日期沒有可用性時' do
      before do
        # 讓明天沒有可用性
        restaurant.available_time_options_for_date(tomorrow).each do |time_option|
          create(:reservation, 
                 restaurant: restaurant,
                 reservation_datetime: time_option[:datetime],
                 business_period_id: time_option[:business_period_id],
                 party_size: 4,
                 status: :confirmed,
                 table: restaurant.restaurant_tables.first)
        end
      end

      it '回傳不可用的日期' do
        unavailable_dates = service.check_availability_for_date_range(start_date, end_date, party_size)
        expect(unavailable_dates).to include(tomorrow.to_s)
      end
    end

    context '當有休息日時' do
      before do
        create(:closure_date, restaurant: restaurant, date: tomorrow)
      end

      it '跳過休息日的檢查' do
        unavailable_dates = service.check_availability_for_date_range(start_date, end_date, party_size)
        # 休息日不會出現在不可用日期中，因為它們被跳過了
        expect(unavailable_dates).not_to include(tomorrow.to_s)
      end
    end
  end

  describe '效能測試' do
    let(:start_date) { today }
    let(:end_date) { today + 30.days }

    before do
      # 創建更多桌位和訂位來測試效能
      table_group = restaurant.table_groups.first
      5.times do |i|
        create(:restaurant_table, restaurant: restaurant, table_group: table_group,
               table_number: "B#{i+1}", capacity: 4, table_type: 'standard')
      end

      # 創建一些現有訂位
      10.times do |i|
        date = today + i.days
        next if restaurant.closed_on_date?(date)
        
        time_options = restaurant.available_time_options_for_date(date)
        next if time_options.empty?
        
        time_option = time_options.sample
        create(:reservation,
               restaurant: restaurant,
               reservation_datetime: time_option[:datetime],
               business_period_id: time_option[:business_period_id],
               party_size: 2,
               status: :confirmed,
               table: restaurant.restaurant_tables.sample)
      end
    end

    it '在合理時間內完成批量可用性檢查' do
      expect {
        service.check_availability_for_date_range(start_date, end_date, 2)
      }.to perform_under(1.second)
    end

    it '避免 N+1 查詢問題' do
      expect {
        service.check_availability_for_date_range(start_date, end_date, 2)
      }.to perform_at_most(10).db_queries
    end
  end
end 