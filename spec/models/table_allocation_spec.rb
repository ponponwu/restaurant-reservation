require 'rails_helper'

RSpec.describe '桌位分配系統' do
  let(:restaurant) { create(:restaurant) }

  before do
    # 設置餐廳基本政策
    policy = restaurant.reservation_policy || restaurant.create_reservation_policy
    policy.update!(
      max_party_size: 20,
      min_party_size: 1,
      advance_booking_days: 30,
      minimum_advance_hours: 1
    )
  end

  describe 'Restaurant#allow_table_combinations' do
    it '餐廳應該允許併桌' do
      expect(restaurant.allow_table_combinations).to be true
    end
  end

  describe 'RestaurantTable 桌位容量驗證' do
    let(:table_group) { create(:table_group, restaurant: restaurant) }

    context '單一桌位適合性檢查' do
      let(:table) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, min_capacity: 2, max_capacity: 6) }

      it '應該接受適合範圍內的人數' do
        expect(table.suitable_for?(2)).to be true
        expect(table.suitable_for?(4)).to be true
        expect(table.suitable_for?(6)).to be true
      end

      it '應該拒絕超出範圍的人數' do
        expect(table.suitable_for?(1)).to be false
        expect(table.suitable_for?(7)).to be false
      end

      it '應該檢查桌位可用狀態' do
        table.update!(operational_status: 'maintenance')
        expect(table.suitable_for?(4)).to be false
      end
    end

    context '不同桌位類型的約束' do
      it '吧台座位應該只能容納1人' do
        bar_table = create(:table, :bar_seat, restaurant: restaurant, table_group: table_group)

        expect(bar_table.suitable_for?(1)).to be true
        expect(bar_table.suitable_for?(2)).to be false
      end

      it '窗邊圓桌應該有最小人數限制' do
        window_table = create(:table, :window_round_table, restaurant: restaurant, table_group: table_group)

        expect(window_table.suitable_for?(3)).to be false  # 低於最小值4
        expect(window_table.suitable_for?(4)).to be true   # 等於最小值
        expect(window_table.suitable_for?(5)).to be true   # 等於最大值
        expect(window_table.suitable_for?(6)).to be false  # 超過最大值
      end
    end
  end

  describe 'Reservation 訂位驗證' do
    let(:business_period) do
      create(:business_period,
             restaurant: restaurant,
             start_time: '11:30',
             end_time: '14:30',
             days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
    end

    context '人數驗證' do
      it '應該要求大人數和小孩數的總和等於總人數' do
        reservation = build(:reservation,
                            restaurant: restaurant,
                            business_period: business_period,
                            party_size: 4,
                            adults_count: 2,
                            children_count: 1) # 總和只有3，不等於party_size的4

        expect(reservation).not_to be_valid
        expect(reservation.errors[:party_size]).to include('大人數和小孩數的總和必須等於總人數')
      end

      it '應該接受正確的人數組合' do
        reservation = build(:reservation,
                            restaurant: restaurant,
                            business_period: business_period,
                            party_size: 4,
                            adults_count: 2,
                            children_count: 2)

        expect(reservation).to be_valid
      end
    end

    context '餐廳人數限制' do
      it '應該遵守餐廳的最大人數限制' do
        restaurant.reservation_policy.update!(max_party_size: 10)

        reservation = build(:reservation,
                            restaurant: restaurant,
                            business_period: business_period,
                            party_size: 15,
                            adults_count: 15,
                            children_count: 0)

        expect(reservation).not_to be_valid
        expect(reservation.errors[:party_size]).to include('人數不能超過 10 人')
      end
    end

    context '預約時間驗證' do
      it '應該要求預約時間在未來' do
        past_time = 1.hour.ago
        reservation = build(:reservation,
                            restaurant: restaurant,
                            business_period: business_period,
                            reservation_datetime: past_time)

        expect(reservation).not_to be_valid
      end
    end
  end

  describe '桌位分配優先級系統' do
    let(:table_group_window) { create(:table_group, restaurant: restaurant, name: '窗邊圓桌', sort_order: 1) }
    let(:table_group_square) { create(:table_group, restaurant: restaurant, name: '方桌', sort_order: 2) }
    let(:table_group_bar) { create(:table_group, restaurant: restaurant, name: '吧台', sort_order: 3) }

    let!(:window_table) { create(:table, :window_round_table, restaurant: restaurant, table_group: table_group_window, sort_order: 1) }
    let!(:square_table_a) { create(:table, :square_table, restaurant: restaurant, table_group: table_group_square, table_number: '方桌A', sort_order: 1) }
    let!(:square_table_b) { create(:table, :square_table, restaurant: restaurant, table_group: table_group_square, table_number: '方桌B', sort_order: 2) }
    let!(:bar_table_a) { create(:table, :bar_seat, restaurant: restaurant, table_group: table_group_bar, table_number: '吧台A', sort_order: 1) }

    context 'TableGroup 排序' do
      it '應該按照 sort_order 排序桌位群組' do
        groups = restaurant.table_groups.ordered

        expect(groups.first.name).to eq('窗邊圓桌')
        expect(groups.second.name).to eq('方桌')
        expect(groups.third.name).to eq('吧台')
      end
    end

    context 'RestaurantTable 全域優先級' do
      it '應該正確計算全域優先級' do
        expect(window_table.global_priority).to eq(1)
        expect(square_table_a.global_priority).to eq(2)
        expect(square_table_b.global_priority).to eq(3)
        expect(bar_table_a.global_priority).to eq(4)
      end
    end
  end

  describe '營業時段和桌位衝突檢查' do
    let(:business_period) do
      create(:business_period,
             restaurant: restaurant,
             start_time: '11:30',
             end_time: '14:30',
             days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
    end

    let(:table_group) { create(:table_group, restaurant: restaurant) }
    let(:table) { create(:table, restaurant: restaurant, table_group: table_group) }

    context 'RestaurantTable#available_for_datetime?' do
      let(:base_time) { 1.day.from_now.change(hour: 12, min: 0) }

      it '空桌位應該可用' do
        expect(table.available_for_datetime?(base_time)).to be true
      end

      context '當有重疊的訂位時' do
        before do
          # 建立一個在相同時間的訂位
          create(:reservation, :confirmed,
                 restaurant: restaurant,
                 business_period: business_period,
                 table: table,
                 reservation_datetime: base_time)
        end

        it '應該顯示不可用' do
          expect(table.available_for_datetime?(base_time)).to be false
        end

        it '應該檢查時間重疊（前後2小時）' do
          # 1小時後的時間應該還是不可用（因為重疊）
          later_time = base_time + 1.hour
          expect(table.available_for_datetime?(later_time)).to be false

          # 3小時後的時間應該可用
          much_later_time = base_time + 3.hours
          expect(table.available_for_datetime?(much_later_time)).to be true
        end
      end
    end
  end

  describe '餐廳容量計算' do
    let(:table_group) { create(:table_group, restaurant: restaurant) }

    before do
      # 建立不同容量的桌位
      create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, max_capacity: 6)
      create(:table, restaurant: restaurant, table_group: table_group, capacity: 2, max_capacity: 2)
      create(:table, restaurant: restaurant, table_group: table_group, capacity: 1, max_capacity: 1)
      create(:table, :inactive, restaurant: restaurant, table_group: table_group, capacity: 8, max_capacity: 8) # 不活躍的桌位
    end

    it '應該正確計算總容量（使用 max_capacity）' do
      expected_capacity = 6 + 2 + 1  # 不包含不活躍的桌位
      expect(restaurant.calculate_total_capacity).to eq(expected_capacity)
    end

    it '應該更新快取的容量' do
      restaurant.update_cached_capacity
      expect(restaurant.total_capacity).to eq(restaurant.calculate_total_capacity)
    end

    it '應該只計算活躍桌位的容量' do
      total_tables = restaurant.restaurant_tables.count
      active_tables = restaurant.restaurant_tables.active.count

      expect(total_tables).to eq(4)  # 包含不活躍的
      expect(active_tables).to eq(3) # 只有活躍的
    end
  end

  describe 'TableCombination 併桌功能' do
    let(:table_group) { create(:table_group, restaurant: restaurant) }
    let(:business_period) do
      create(:business_period,
             restaurant: restaurant,
             start_time: '11:30',
             end_time: '14:30',
             days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
    end

    context '併桌驗證' do
      let(:table1) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4) }
      let(:table2) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 2) }
      let(:reservation) { create(:reservation, restaurant: restaurant, business_period: business_period, party_size: 6, adults_count: 6, children_count: 0) }

      it '應該允許建立桌位組合' do
        combination = TableCombination.new(
          reservation: reservation,
          name: '大型聚會併桌'
        )

        # 透過 table_combination_tables 建立關聯
        combination.table_combination_tables.build(restaurant_table: table1)
        combination.table_combination_tables.build(restaurant_table: table2)

        expect { combination.save! }.not_to raise_error
      end

      it '應該正確計算組合的總容量' do
        combination = TableCombination.new(
          reservation: reservation,
          name: '大型聚會併桌'
        )

        # 透過 table_combination_tables 建立關聯
        combination.table_combination_tables.build(restaurant_table: table1)
        combination.table_combination_tables.build(restaurant_table: table2)
        combination.save!

        expect(combination.total_capacity).to eq(table1.capacity + table2.capacity)
      end
    end
  end

  describe '資料完整性和約束' do
    let(:table_group) { create(:table_group, restaurant: restaurant) }
    let(:business_period) do
      create(:business_period,
             restaurant: restaurant,
             start_time: '11:30',
             end_time: '14:30',
             days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
    end

    context '必要欄位驗證' do
      it 'Restaurant 需要名稱和電話' do
        restaurant = build(:restaurant, name: nil, phone: nil)

        expect(restaurant).not_to be_valid
        expect(restaurant.errors[:name]).to be_present
        expect(restaurant.errors[:phone]).to be_present
      end

      it 'RestaurantTable 需要桌號和容量' do
        table = RestaurantTable.new(restaurant: restaurant, table_group: table_group, table_number: nil, capacity: nil)

        expect(table).not_to be_valid
        expect(table.errors[:table_number]).to be_present
        expect(table.errors[:capacity]).to be_present
      end

      it 'Reservation 需要客戶資訊和時間' do
        reservation = build(:reservation,
                            restaurant: restaurant,
                            business_period: business_period,
                            customer_name: nil,
                            customer_phone: nil,
                            reservation_datetime: nil)

        expect(reservation).not_to be_valid
        expect(reservation.errors[:customer_name]).to be_present
        expect(reservation.errors[:customer_phone]).to be_present
        expect(reservation.errors[:reservation_datetime]).to be_present
      end
    end

    context '關聯完整性' do
      let(:table) { create(:table, restaurant: restaurant, table_group: table_group) }

      it '餐廳應該有關聯的訂位' do
        reservation = create(:reservation, restaurant: restaurant, business_period: business_period, table: table,
                                           party_size: 2, adults_count: 2, children_count: 0)

        expect(restaurant.reservations).to include(reservation)
        expect(reservation.restaurant).to eq(restaurant)
      end

      it '桌位應該有關聯的訂位' do
        reservation = create(:reservation, :confirmed, restaurant: restaurant, business_period: business_period, table: table,
                                                       party_size: 2, adults_count: 2, children_count: 0)

        expect(table.reservations).to include(reservation)
        expect(reservation.table).to eq(table)
      end
    end
  end

  describe '效能考量' do
    let(:table_group) { create(:table_group, restaurant: restaurant) }

    before do
      # 建立大量桌位進行效能測試
      20.times do |i|
        create(:table, restaurant: restaurant, table_group: table_group, table_number: "Table-#{i}")
      end
    end

    it '桌位查詢應該有效率' do
      # 這個測試確保查詢效能
      start_time = Time.current
      restaurant.restaurant_tables.active.available_for_booking.count
      end_time = Time.current

      expect(end_time - start_time).to be < 0.1.seconds
    end

    it '批次操作應該有效率' do
      # 測試批次更新桌位狀態
      start_time = Time.current

      restaurant.restaurant_tables.update_all(status: 'maintenance')

      end_time = Time.current
      expect(end_time - start_time).to be < 1.second
    end
  end

  describe '複雜的桌位分配情境' do
    let(:restaurant) { create(:restaurant) }
    let!(:business_period) { create(:business_period, restaurant: restaurant) }

    context '併桌功能測試' do
      it '應該能正確計算併桌後的總容量' do
        table1 = create(:table, restaurant: restaurant, max_capacity: 4)
        table2 = create(:table, restaurant: restaurant, max_capacity: 6)

        combination = create(:table_combination, restaurant: restaurant)
        create(:table_combination_table, table_combination: combination, restaurant_table: table1)
        create(:table_combination_table, table_combination: combination, restaurant_table: table2)

        expect(combination.total_capacity).to eq(10)
      end

      it '併桌應該考慮桌位的物理位置相鄰性' do
        # 建立相鄰的桌位
        adjacent_table1 = create(:table, restaurant: restaurant, max_capacity: 4,
                                         table_number: 'A1', position_x: 1, position_y: 1)
        adjacent_table2 = create(:table, restaurant: restaurant, max_capacity: 4,
                                         table_number: 'A2', position_x: 2, position_y: 1)

        # 建立不相鄰的桌位
        distant_table = create(:table, restaurant: restaurant, max_capacity: 4,
                                       table_number: 'B1', position_x: 10, position_y: 10)

        # 測試相鄰性檢查
        expect(adjacent_table1.adjacent_to?(adjacent_table2)).to be true
        expect(adjacent_table1.adjacent_to?(distant_table)).to be false
      end

      it '應該限制併桌的最大桌位數量' do
        tables = Array.new(5) do |_i|
          create(:table, restaurant: restaurant, max_capacity: 4)
        end

        combination = create(:table_combination, restaurant: restaurant)

        # 嘗試併4張桌（應該成功）
        4.times do |i|
          create(:table_combination_table,
                 table_combination: combination,
                 restaurant_table: tables[i])
        end

        expect(combination.restaurant_tables.count).to eq(4)
        expect(combination.valid?).to be true

        # 嘗試添加第5張桌（應該失敗或受限）
        expect do
          create(:table_combination_table,
                 table_combination: combination,
                 restaurant_table: tables[4])
        end.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context '時間衝突複雜情境' do
      let(:table) { create(:table, restaurant: restaurant, max_capacity: 4) }
      let(:base_datetime) { 1.day.from_now.change(hour: 12, min: 0) }

      it '應該正確處理用餐時間的緩衝區間' do
        # 第一個訂位：12:00-14:00
        create(:reservation, :confirmed,
               restaurant: restaurant,
               business_period: business_period,
               table: table,
               reservation_datetime: base_datetime,
               party_size: 2)

        # 檢查13:30不可用（在用餐時間內）
        expect(table.available_for_datetime?(base_datetime + 1.5.hours)).to be false

        # 檢查14:30可用（緩衝時間後）
        expect(table.available_for_datetime?(base_datetime + 2.5.hours)).to be true

        # 檢查11:30不可用（緩衝時間前）
        expect(table.available_for_datetime?(base_datetime - 0.5.hours)).to be false
      end

      it '應該處理跨日訂位的時間計算' do
        # 深夜訂位：23:30
        late_night = base_datetime.change(hour: 23, min: 30)
        create(:reservation, :confirmed,
               restaurant: restaurant,
               business_period: business_period,
               table: table,
               reservation_datetime: late_night,
               party_size: 2)

        # 檢查隔天凌晨1:00不可用
        next_day_early = late_night + 1.5.hours
        expect(table.available_for_datetime?(next_day_early)).to be false

        # 檢查隔天凌晨3:00可用
        next_day_late = late_night + 3.5.hours
        expect(table.available_for_datetime?(next_day_late)).to be true
      end
    end

    context '特殊營業時段處理' do
      it '應該正確處理假日營業時間' do
        # 建立假日營業時段
        holiday_period = create(:business_period,
                                restaurant: restaurant,
                                start_time: '10:00',
                                end_time: '22:00',
                                days_of_week: %w[saturday sunday])

        saturday_time = 1.week.from_now.beginning_of_week + 5.days + 11.hours
        table = create(:table, restaurant: restaurant)

        reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: holiday_period,
                             table: table,
                             reservation_datetime: saturday_time,
                             party_size: 2)

        expect(reservation.valid?).to be true
        expect(reservation.business_period).to eq(holiday_period)
      end

      it '應該處理季節性營業時間調整' do
        # 建立夏季營業時段（延長營業）
        summer_period = create(:business_period,
                               restaurant: restaurant,
                               start_time: '11:00',
                               end_time: '23:00',
                               valid_from: Date.current.beginning_of_month,
                               valid_until: Date.current.end_of_month)

        # 建立冬季營業時段（縮短營業）
        winter_period = create(:business_period,
                               restaurant: restaurant,
                               start_time: '12:00',
                               end_time: '21:00',
                               valid_from: (Date.current + 1.month).beginning_of_month,
                               valid_until: (Date.current + 1.month).end_of_month)

        table = create(:table, restaurant: restaurant)

        # 夏季22:30的訂位應該有效
        summer_time = Date.current.change(hour: 22, min: 30)
        summer_reservation = build(:reservation,
                                   restaurant: restaurant,
                                   business_period: summer_period,
                                   table: table,
                                   reservation_datetime: summer_time,
                                   party_size: 2)

        expect(summer_reservation.valid?).to be true

        # 冬季22:30的訂位應該無效
        winter_time = (Date.current + 1.month).change(hour: 22, min: 30)
        winter_reservation = build(:reservation,
                                   restaurant: restaurant,
                                   business_period: winter_period,
                                   table: table,
                                   reservation_datetime: winter_time,
                                   party_size: 2)

        expect(winter_reservation.valid?).to be false
      end
    end

    context '容量計算邊界測試' do
      it '應該正確計算混合桌位類型的總容量' do
        create(:table, restaurant: restaurant, table_type: 'square', max_capacity: 2, count: 4)
        create(:table, restaurant: restaurant, table_type: 'round', max_capacity: 6, count: 2)
        create(:table, restaurant: restaurant, table_type: 'bar', max_capacity: 1, count: 8)

        total_capacity = restaurant.calculate_total_capacity
        expected_capacity = (2 * 4) + (6 * 2) + (1 * 8) # 8 + 12 + 8 = 28

        expect(total_capacity).to eq(expected_capacity)
      end

      it '應該考慮桌位的最小容量限制' do
        table = create(:table, restaurant: restaurant,
                               min_capacity: 2, max_capacity: 6)

        # 1人訂位應該不適合
        expect(table.suitable_for?(1)).to be false

        # 2-6人訂位應該適合
        (2..6).each do |party_size|
          expect(table.suitable_for?(party_size)).to be true
        end

        # 7人訂位應該不適合
        expect(table.suitable_for?(7)).to be false
      end

      it '應該處理動態容量調整（如可移動座椅）' do
        flexible_table = create(:table, restaurant: restaurant,
                                        min_capacity: 2, max_capacity: 8,
                                        table_type: 'round',
                                        is_flexible: true)

        # 小聚會時應該適合
        expect(flexible_table.suitable_for?(3)).to be true

        # 大聚會時也應該適合
        expect(flexible_table.suitable_for?(7)).to be true

        # 超過最大容量時不適合
        expect(flexible_table.suitable_for?(9)).to be false
      end
    end

    context '特殊需求處理' do
      it '應該標記適合兒童的桌位' do
        child_friendly_table = create(:table, restaurant: restaurant,
                                              table_type: 'round',
                                              is_child_friendly: true,
                                              has_high_chair: true)

        bar_table = create(:table, restaurant: restaurant,
                                   table_type: 'bar',
                                   is_child_friendly: false)

        # 有兒童的訂位
        family_reservation = build(:reservation,
                                   restaurant: restaurant,
                                   business_period: business_period,
                                   party_size: 3,
                                   adults_count: 2,
                                   children_count: 1)

        expect(child_friendly_table.suitable_for_reservation?(family_reservation)).to be true
        expect(bar_table.suitable_for_reservation?(family_reservation)).to be false
      end
    end
  end
end
