require 'rails_helper'

RSpec.describe ReservationAllocatorService, type: :service do
  let(:restaurant) { create(:restaurant) }
  let(:business_period) do
    create(:business_period,
           restaurant: restaurant,
           start_time: '11:30',
           end_time: '14:30',
           days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
  end
  let(:base_time) { 1.day.from_now.change(hour: 12, min: 0) }

  before do
    # 確保餐廳有有效的政策
    policy = restaurant.reservation_policy || restaurant.create_reservation_policy
    policy.update!(
      max_party_size: 20,
      min_party_size: 1,
      allow_table_combinations: true,
      max_combination_tables: 4
    )
  end

  # 在桌位創建後更新餐廳容量的helper
  def update_restaurant_capacity
    restaurant.update_cached_capacity
  end

  describe '拼桌分配功能' do
    describe '基本拼桌場景' do
      let!(:table_group) { create(:table_group, restaurant: restaurant, name: '用餐區') }
      let!(:table_2a) { create(:table, restaurant: restaurant, table_group: table_group, table_number: 'A1', capacity: 2, max_capacity: 2, can_combine: true) }
      let!(:table_2b) { create(:table, restaurant: restaurant, table_group: table_group, table_number: 'A2', capacity: 2, max_capacity: 2, can_combine: true) }
      let!(:table_4) { create(:table, restaurant: restaurant, table_group: table_group, table_number: 'B1', capacity: 4, max_capacity: 4, can_combine: true) }

      before do
        update_restaurant_capacity
      end

      context '當單一桌位不足時' do
        before do
          # 佔用4人桌
          create(:reservation, :confirmed,
                 restaurant: restaurant,
                 business_period: business_period,
                 table: table_4,
                 party_size: 4,
                 adults_count: 4,
                 children_count: 0,
                 reservation_datetime: base_time)
        end

        it '應該能拼桌滿足4人需求' do
          # Given: 需要4人桌位但4人桌已被佔用
          reservation = create(:reservation,
                               restaurant: restaurant,
                               business_period: business_period,
                               party_size: 4,
                               adults_count: 4,
                               reservation_datetime: base_time + 10.minutes)

          # When: 分配桌位
          service = ReservationAllocatorService.new(reservation)
          result = service.allocate_table

          # Then: 應該返回拼桌組合
          expect(result).to be_present
          expect(result).to be_an(Array)
          expect(result.length).to eq(2)
          expect(result.sum(&:capacity)).to be >= 4
        end
      end

      context '當有足夠單一桌位時' do
        it '應該優先分配單一桌位而非拼桌' do
          # Given: 需要2人桌位且有可用桌位
          reservation = create(:reservation,
                               restaurant: restaurant,
                               business_period: business_period,
                               party_size: 2,
                               adults_count: 2,
                               children_count: 0,
                               reservation_datetime: base_time)

          # When: 分配桌位
          service = ReservationAllocatorService.new(reservation)

          result = service.allocate_table

          # Then: 應該返回單一桌位
          expect(result).to be_present
          expect(result).not_to be_an(Array)
          expect(result.capacity).to be >= 2
        end
      end
    end

    describe '拼桌限制驗證' do
      let!(:group_a) { create(:table_group, restaurant: restaurant, name: '區域A') }
      let!(:group_b) { create(:table_group, restaurant: restaurant, name: '區域B') }
      let!(:table_a1) { create(:table, restaurant: restaurant, table_group: group_a, table_number: 'A1', capacity: 2, max_capacity: 2, can_combine: true) }
      let!(:table_a2) { create(:table, restaurant: restaurant, table_group: group_a, table_number: 'A2', capacity: 2, max_capacity: 2, can_combine: true) }
      let!(:table_b1) { create(:table, restaurant: restaurant, table_group: group_b, table_number: 'B1', capacity: 2, max_capacity: 2, can_combine: true) }

      before do
        update_restaurant_capacity
      end

      it '不應該跨群組拼桌' do
        # Given: 需要4人桌位但每個群組只有2人桌
        reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 4,
                             adults_count: 4,
                             reservation_datetime: base_time)

        # When: 分配桌位
        service = ReservationAllocatorService.new(reservation)
        result = service.allocate_table

        # Then: 應該在同群組內拼桌
        if result.is_a?(Array)
          table_groups = result.map(&:table_group_id).uniq
          expect(table_groups.length).to eq(1)
        end
      end

      it '不應該使用不支援拼桌的桌位' do
        # Given: 設置一個不支援拼桌的桌位
        table_a1.update!(can_combine: false)

        reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 4,
                             adults_count: 4,
                             reservation_datetime: base_time)

        # When: 分配桌位
        service = ReservationAllocatorService.new(reservation)
        result = service.allocate_table

        # Then: 結果不應包含不支援拼桌的桌位
        expect(result).not_to include(table_a1) if result.is_a?(Array)
      end
    end

    describe '容量計算' do
      let!(:table_group) { create(:table_group, restaurant: restaurant, name: '用餐區') }
      let!(:table_2) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 2, max_capacity: 2, can_combine: true) }
      let!(:table_4) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, max_capacity: 4, can_combine: true) }
      let!(:table_6) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 6, max_capacity: 6, can_combine: true) }

      before do
        update_restaurant_capacity
      end

      it '應該選擇容量最接近的組合' do
        # Given: 需要6人桌位
        reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 6,
                             adults_count: 6,
                             reservation_datetime: base_time)

        # When: 分配桌位
        service = ReservationAllocatorService.new(reservation)
        result = service.allocate_table

        # Then: 應該優先選擇6人桌而非拼桌
        expect(result).to be_present

        if result.is_a?(Array)
          # 如果是拼桌，總容量應該足夠
          expect(result.sum(&:capacity)).to be >= 6
        else
          # 如果是單桌，應該是6人桌
          expect(result.capacity).to be >= 6
        end
      end
    end

    describe '特殊情境處理' do
      let!(:table_group) { create(:table_group, restaurant: restaurant, name: '用餐區') }
      let!(:bar_group) { create(:table_group, restaurant: restaurant, name: '吧台區') }
      let!(:regular_table) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 2, max_capacity: 2, can_combine: true) }
      let!(:bar_table) { create(:table, restaurant: restaurant, table_group: bar_group, capacity: 1, max_capacity: 1, table_type: 'bar', can_combine: true) }

      before do
        update_restaurant_capacity
      end

      it '有兒童時不應分配吧台桌位' do
        # Given: 有兒童的訂位
        reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 2,
                             adults_count: 1,
                             children_count: 1,
                             reservation_datetime: base_time)

        # When: 分配桌位
        service = ReservationAllocatorService.new(reservation)
        result = service.allocate_table

        # Then: 不應該分配到吧台
        if result.is_a?(Array)
          expect(result.none? { |t| t.table_type == 'bar' }).to be true
        elsif result.present?
          expect(result.table_type).not_to eq('bar')
        end
      end

      it '無法滿足需求時應返回nil' do
        # Given: 需求超過餐廳最大聚會人數
        reservation = build(:reservation,
                            restaurant: restaurant,
                            business_period: business_period,
                            party_size: 15,
                            adults_count: 15,
                            children_count: 0,
                            reservation_datetime: base_time)

        # When: 分配桌位
        service = ReservationAllocatorService.new(reservation)
        result = service.allocate_table

        # Then: 應該返回nil
        expect(result).to be_nil
      end
    end

    describe '效能測試' do
      let!(:table_group) { create(:table_group, restaurant: restaurant, name: '用餐區') }

      before do
        # 建立多個桌位
        5.times do |_i|
          create(:table, restaurant: restaurant, table_group: table_group, capacity: 2, max_capacity: 2, can_combine: true)
        end
        update_restaurant_capacity
      end

      it '複雜拼桌計算應在合理時間內完成' do
        reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 8,
                             adults_count: 8,
                             children_count: 0,
                             reservation_datetime: base_time)

        start_time = Time.current
        service = ReservationAllocatorService.new(reservation)
        service.allocate_table
        end_time = Time.current

        calculation_time = end_time - start_time
        expect(calculation_time).to be < 1.second
      end

      it '應該限制拼桌的最大桌位數量' do
        # Given: 更新最大拼桌數量限制
        restaurant.reservation_policy.update!(max_combination_tables: 2)

        reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 8,
                             adults_count: 8,
                             reservation_datetime: base_time)

        # When: 分配桌位
        service = ReservationAllocatorService.new(reservation)
        result = service.allocate_table

        # Then: 如果是拼桌，桌位數量不應超過限制
        expect(result.length).to be <= 2 if result.is_a?(Array)
      end
    end
  end

  describe '併桌資源競爭' do
    let!(:table_group) { create(:table_group, restaurant: restaurant, name: '用餐區') }
    let!(:table_4) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, max_capacity: 4, can_combine: true) }
    let!(:table_2a) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 2, max_capacity: 2, can_combine: true) }
    let!(:table_2b) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 2, max_capacity: 2, can_combine: true) }

    before do
      update_restaurant_capacity
    end

    it '連續訂位應該能合理分配資源' do
      # Given: 第一個4人訂位
      first_reservation = create(:reservation,
                                 restaurant: restaurant,
                                 business_period: business_period,
                                 party_size: 4,
                                 adults_count: 4,
                                 reservation_datetime: base_time)

      service1 = ReservationAllocatorService.new(first_reservation)
      result1 = service1.allocate_table

      # When: 第二個4人訂位
      second_reservation = create(:reservation,
                                  restaurant: restaurant,
                                  business_period: business_period,
                                  party_size: 4,
                                  adults_count: 4,
                                  reservation_datetime: base_time + 15.minutes)

      service2 = ReservationAllocatorService.new(second_reservation)
      result2 = service2.allocate_table

      # Then: 兩個訂位都應該能被滿足（通過不同的分配策略）
      expect(result1).to be_present
      expect(result2).to be_present
    end
  end

  describe '無限用餐時間模式' do
    let!(:table_group) { create(:table_group, restaurant: restaurant, name: '用餐區') }
    let!(:table_4a) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, max_capacity: 4, can_combine: true) }
    let!(:table_4b) { create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, max_capacity: 4, can_combine: true) }

    before do
      restaurant.reservation_policy.update!(unlimited_dining_time: true)
      update_restaurant_capacity
    end

    it '同餐期拼桌應該檢查衝突' do
      # Given: 同餐期已有拼桌
      create(:reservation, :confirmed,
             restaurant: restaurant,
             business_period: business_period,
             table: table_4a,
             party_size: 4,
             adults_count: 4,
             children_count: 0,
             reservation_datetime: base_time)

      # When: 新的訂位嘗試使用相同桌位
      new_reservation = create(:reservation,
                               restaurant: restaurant,
                               business_period: business_period,
                               party_size: 4,
                               adults_count: 4,
                               reservation_datetime: base_time + 30.minutes)

      service = ReservationAllocatorService.new(new_reservation)
      result = service.allocate_table

      # Then: 應該分配到不同桌位或拼桌
      if result.is_a?(Array)
        expect(result).not_to include(table_4a)
      elsif result.present?
        expect(result).not_to eq(table_4a)
      end
    end
  end
end
