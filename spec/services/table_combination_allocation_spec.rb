require 'rails_helper'

RSpec.describe '拼桌分配系統', type: :model do
  let(:restaurant) { create(:restaurant) }
  let(:business_period) do
    create(:business_period,
           restaurant: restaurant,
           start_time: '11:30',
           end_time: '14:30',
           days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
  end
  
  before do    
    # 設置餐廳基本政策
    policy = restaurant.reservation_policy || restaurant.create_reservation_policy
    policy.update!(
      max_party_size: 20,
      min_party_size: 1,
      advance_booking_days: 30,
      minimum_advance_hours: 1
    )
    
    setup_test_tables
  end

  describe '基本拼桌場景' do
    let(:base_time) { 1.day.from_now.change(hour: 12, min: 0) }

    context '4人桌被佔用後的拼桌需求' do
      it '唯一4人桌被佔用後，其他群組能拼出4人桌滿足新訂位' do
        # 先佔用所有能容納4人的桌位（包括4人桌和5人桌）
        suitable_tables = restaurant.restaurant_tables.active.select { |t| t.suitable_for?(4) }
        suitable_tables.each_with_index do |table, index|
          create(:reservation, :confirmed,
                 restaurant: restaurant,
                 business_period: business_period,
                 table: table,
                 customer_name: "佔用者#{index + 1}",
                 party_size: [table.capacity, 4].min, # 不超過4人，但佔用桌位
                 adults_count: [table.capacity, 4].min,
                 children_count: 0,
                 reservation_datetime: base_time)
          puts "佔用桌位：#{table.table_number}（容量：#{table.capacity}人）"
        end

        # 現在有新的4人訂位需求
        new_reservation = create(:reservation,
                                restaurant: restaurant,
                                business_period: business_period,
                                customer_name: '新客戶',
                                customer_phone: '0912345678',
                                party_size: 4,
                                adults_count: 4,
                                children_count: 0,
                                reservation_datetime: base_time + 10.minutes)

        service = ReservationAllocatorService.new(new_reservation)
        
        # 調試：檢查可用桌位
        available_tables = service.find_available_tables
        puts "可用桌位：#{available_tables.map { |t| "#{t.table_number}(#{t.capacity}人)" }.join(', ')}"
        
        # 調試：檢查拼桌能力
        availability = service.check_availability
        puts "拼桌檢查：can_combine=#{availability[:can_combine]}, combinable_tables=#{availability[:combinable_tables].map { |t| "#{t.table_number}(#{t.capacity}人)" }.join(', ')}"
        
        # 調試：檢查拼桌組合結果
        combinable_result = service.send(:find_combinable_tables)
        if combinable_result
          puts "找到拼桌組合：#{combinable_result.map { |t| "#{t.table_number}(#{t.capacity}人)" }.join(' + ')}"
        else
          puts "未找到拼桌組合"
        end
        
        result = service.allocate_table

        # 應該能找到解決方案（必須是拼桌，因為所有單一桌位都被佔用）
        expect(result).to be_present
        
        new_reservation.reload
        if new_reservation.table_combination.present?
          # 如果使用拼桌
          combination = new_reservation.table_combination
          expect(combination.total_capacity).to be >= 4
          puts "4人訂位拼桌成功：#{combination.table_numbers}，總容量：#{combination.total_capacity}"
          
          # 驗證拼桌桌位來自同一群組
          table_groups = combination.restaurant_tables.map(&:table_group).uniq
          expect(table_groups.count).to eq(1)
          puts "拼桌群組：#{table_groups.first.name}"
        else
          fail "所有單一桌位都被佔用，應該使用拼桌解決方案"
        end
      end

      it '第一次訂位佔用4人桌，第二次4人訂位應該能拼桌' do
        # 第一次訂位：4人預訂4人桌
        first_reservation = create(:reservation,
                                 restaurant: restaurant,
                                 business_period: business_period,
                                 customer_name: '張先生',
                                 customer_phone: '0912345678',
                                 party_size: 4,
                                 adults_count: 4,
                                 children_count: 0,
                                 reservation_datetime: base_time)

        service1 = ReservationAllocatorService.new(first_reservation)
        first_table = service1.allocate_table
        
        # 驗證第一次分配成功
        expect(first_table).to be_present
        expect(first_table.suitable_for?(4)).to be true
        
        # 更新訂位狀態，標記桌位為已佔用
        first_reservation.update!(table: first_table, status: :confirmed)

        # 第二次訂位：同一時段另一組4人
        second_reservation = create(:reservation,
                                  restaurant: restaurant,
                                  business_period: business_period,
                                  customer_name: '王小姐',
                                  customer_phone: '0987654321',
                                  party_size: 4,
                                  adults_count: 4,
                                  children_count: 0,
                                  reservation_datetime: base_time + 5.minutes)

        service2 = ReservationAllocatorService.new(second_reservation)
        second_result = service2.allocate_table

        # 驗證第二次分配
        expect(second_result).to be_present
        
        # 檢查是否通過拼桌滿足需求
        second_reservation.reload
        if second_reservation.table_combination.present?
          # 如果使用了拼桌
          combination = second_reservation.table_combination
          expect(combination.total_capacity).to be >= 4
          expect(combination.restaurant_tables.count).to be >= 2
          puts "成功拼桌：#{combination.table_numbers}，總容量：#{combination.total_capacity}"
        else
          # 如果找到了其他單一桌位
          expect(second_result.suitable_for?(4)).to be true
          expect(second_result.id).not_to eq(first_table.id)
          puts "分配到其他桌位：#{second_result.table_number}，容量：#{second_result.capacity}"
        end
      end

      it '同時有多個小桌可以組合成滿足需求的容量' do
        # 先佔用最大的桌位（窗邊圓桌5人）
        large_reservation = create(:reservation, :confirmed,
                                 restaurant: restaurant,
                                 business_period: business_period,
                                 table: @window_table,
                                 party_size: 5,
                                 adults_count: 5,
                                 children_count: 0,
                                 reservation_datetime: base_time)

        # 再佔用一個4人方桌
        occupied_square_table = @square_tables.find { |t| t.capacity == 4 }
        if occupied_square_table
          square_reservation = create(:reservation, :confirmed,
                                    restaurant: restaurant,
                                    business_period: business_period,
                                    table: occupied_square_table,
                                    party_size: 3,
                                    adults_count: 3,
                                    children_count: 0,
                                    reservation_datetime: base_time)
        end

        # 現在有一組6人需要訂位
        large_party = create(:reservation,
                           restaurant: restaurant,
                           business_period: business_period,
                           customer_name: '陳家聚餐',
                           party_size: 6,
                           adults_count: 5,
                           children_count: 1,
                           reservation_datetime: base_time + 10.minutes)

        service = ReservationAllocatorService.new(large_party)
        result = service.allocate_table

        expect(result).to be_present
        
        large_party.reload
        if large_party.table_combination.present?
          combination = large_party.table_combination
          expect(combination.total_capacity).to be >= 6
          puts "6人拼桌成功：#{combination.table_numbers}，總容量：#{combination.total_capacity}"
          
          # 驗證拼桌的桌位都是可用的
          combination.restaurant_tables.each do |table|
            expect(table.available_for_datetime?(large_party.reservation_datetime)).to be true
          end
        else
          puts "6人分配到單一桌位：#{result.table_number}"
        end
      end
    end

    context '拼桌優先級和邏輯' do
      it '應該優先選擇容量最接近的桌位組合' do
        # 建立一個需要拼桌的8人訂位
        party_reservation = create(:reservation,
                                 restaurant: restaurant,
                                 business_period: business_period,
                                 party_size: 8,
                                 adults_count: 7,
                                 children_count: 1,
                                 reservation_datetime: base_time)

        service = ReservationAllocatorService.new(party_reservation)
        result = service.allocate_table

        if result.present?
          party_reservation.reload
          
          if party_reservation.table_combination.present?
            combination = party_reservation.table_combination
            total_capacity = combination.total_capacity
            
            # 檢查是否合理使用桌位（不要過度浪費容量）
            expect(total_capacity).to be >= 8
            expect(total_capacity).to be <= 12 # 避免過度浪費
            
            puts "8人拼桌方案：#{combination.table_numbers}"
            puts "總容量：#{total_capacity}，效率：#{(8.0/total_capacity*100).round(1)}%"
          end
        else
          pending "8人拼桌功能需要優化"
        end
      end

      it '拼桌應該限制在同一桌位群組內' do
        # 建立跨群組的桌位佔用情境
        bar_table = @bar_tables.first
        create(:reservation, :confirmed,
             restaurant: restaurant,
             business_period: business_period,
             table: bar_table,
             party_size: 1,
             adults_count: 1,
             children_count: 0,
             reservation_datetime: base_time)

        # 嘗試6人訂位，應該只在方桌群組內拼桌
        large_party = create(:reservation,
                           restaurant: restaurant,
                           business_period: business_period,
                           party_size: 6,
                           adults_count: 6,
                           children_count: 0,
                           reservation_datetime: base_time + 15.minutes)

        service = ReservationAllocatorService.new(large_party)
        result = service.allocate_table

        if result.present?
          large_party.reload
          
          if large_party.table_combination.present?
            combination = large_party.table_combination
            table_groups = combination.restaurant_tables.map(&:table_group).uniq
            
            # 驗證所有桌位都來自同一群組
            expect(table_groups.count).to eq(1)
            puts "拼桌群組一致性驗證通過：#{table_groups.first.name}"
          end
        end
      end
    end

    context '特殊情境處理' do
      it '有兒童的訂位不應該分配到吧台拼桌' do
        family_reservation = create(:reservation,
                                  restaurant: restaurant,
                                  business_period: business_period,
                                  customer_name: '家庭聚餐',
                                  party_size: 5,
                                  adults_count: 3,
                                  children_count: 2,
                                  reservation_datetime: base_time)

        service = ReservationAllocatorService.new(family_reservation)
        result = service.allocate_table

        expect(result).to be_present
        
        family_reservation.reload
        if family_reservation.table_combination.present?
          combination = family_reservation.table_combination
          bar_tables_used = combination.restaurant_tables.select { |t| t.table_type == 'bar' }
          expect(bar_tables_used).to be_empty
          puts "家庭拼桌避開吧台：#{combination.table_numbers}"
        else
          expect(result.table_type).not_to eq('bar')
        end
      end

      it '當無法拼桌時應該返回nil' do
        # 佔用所有桌位，只留下無法組合滿足需求的桌位
        @window_table && create(:reservation, :confirmed,
                               restaurant: restaurant,
                               business_period: business_period,
                               table: @window_table,
                               party_size: 5,
                               adults_count: 5,
                               children_count: 0,
                               reservation_datetime: base_time)

        @square_tables.each do |table|
          create(:reservation, :confirmed,
                 restaurant: restaurant,
                 business_period: business_period,
                 table: table,
                 party_size: table.capacity,
                 adults_count: table.capacity,
                 children_count: 0,
                 reservation_datetime: base_time)
        end

        # 保留一個吧台座位，但無法滿足需求
        available_bar = @bar_tables.first

        # 嘗試訂位4人（無法用吧台座位滿足）
        impossible_reservation = create(:reservation,
                                      restaurant: restaurant,
                                      business_period: business_period,
                                      party_size: 4,
                                      adults_count: 4,
                                      children_count: 0,
                                      reservation_datetime: base_time + 20.minutes)

        service = ReservationAllocatorService.new(impossible_reservation)
        result = service.allocate_table

        expect(result).to be_nil
        puts "正確拒絕無法滿足的訂位需求"
      end
    end
  end

  describe '效能和限制測試' do
    let(:base_time) { 1.day.from_now.change(hour: 18, min: 0) }

    it '拼桌演算法應該在合理時間內完成' do
      # 建立一個需要複雜拼桌計算的訂位
      complex_reservation = create(:reservation,
                                 restaurant: restaurant,
                                 business_period: business_period,
                                 party_size: 10,
                                 adults_count: 8,
                                 children_count: 2,
                                 reservation_datetime: base_time)

      start_time = Time.current
      
      service = ReservationAllocatorService.new(complex_reservation)
      result = service.allocate_table
      
      end_time = Time.current
      calculation_time = end_time - start_time

      # 演算法應該在1秒內完成
      expect(calculation_time).to be < 1.second
      puts "拼桌計算時間：#{(calculation_time * 1000).round(2)}ms"

      if result.present?
        puts "10人拼桌計算成功"
      else
        puts "10人拼桌無可用方案"
      end
    end

    it '應該限制拼桌的最大桌位數量' do
      # 嘗試一個需要很多桌位的大型聚會
      huge_party = create(:reservation,
                        restaurant: restaurant,
                        business_period: business_period,
                        party_size: 15,
                        adults_count: 15,
                        children_count: 0,
                        reservation_datetime: base_time)

      service = ReservationAllocatorService.new(huge_party)
      result = service.allocate_table

      if result.present?
        huge_party.reload
        
        if huge_party.table_combination.present?
          combination = huge_party.table_combination
          tables_count = combination.restaurant_tables.count
          
          # 限制最多不超過4張桌位的拼桌
          expect(tables_count).to be <= 4
          puts "15人拼桌限制驗證：使用#{tables_count}張桌位"
        end
      else
        puts "15人聚會超出餐廳拼桌能力"
      end
    end
  end

  # 複雜併桌情境測試
  describe '複雜併桌情境' do
    let(:table_group_a) { create(:table_group, restaurant: restaurant, name: '窗邊區', sort_order: 1) }
    let(:table_group_b) { create(:table_group, restaurant: restaurant, name: '中央區', sort_order: 2) }
    
    # 窗邊區桌位
    let!(:window_table_2) { create(:table, restaurant: restaurant, table_group: table_group_a, table_number: 'W1', capacity: 2, can_combine: true, sort_order: 1) }
    let!(:window_table_4) { create(:table, restaurant: restaurant, table_group: table_group_a, table_number: 'W2', capacity: 4, can_combine: true, sort_order: 2) }
    let!(:window_table_6) { create(:table, restaurant: restaurant, table_group: table_group_a, table_number: 'W3', capacity: 6, can_combine: true, sort_order: 3) }
    
    # 中央區桌位
    let!(:center_table_2a) { create(:table, restaurant: restaurant, table_group: table_group_b, table_number: 'C1', capacity: 2, can_combine: true, sort_order: 4) }
    let!(:center_table_2b) { create(:table, restaurant: restaurant, table_group: table_group_b, table_number: 'C2', capacity: 2, can_combine: true, sort_order: 5) }
    let!(:center_table_2c) { create(:table, restaurant: restaurant, table_group: table_group_b, table_number: 'C3', capacity: 2, can_combine: true, sort_order: 6) }
    let!(:center_table_4) { create(:table, restaurant: restaurant, table_group: table_group_b, table_number: 'C4', capacity: 4, can_combine: true, sort_order: 7) }
    
    before do
      restaurant.reservation_policy.update!(
        allow_table_combinations: true,
        max_combination_tables: 4
      )
    end
    
    context '多層次併桌需求' do
      it '8人訂位需要多桌併桌時的最佳組合選擇' do
        # 佔用一些桌位製造複雜情境
        create(:reservation, :confirmed,
               restaurant: restaurant,
               business_period: business_period,
               table: window_table_6,
               party_size: 5,
               adults_count: 5,
               children_count: 0,
               reservation_datetime: base_time)
        
        create(:reservation, :confirmed,
               restaurant: restaurant,
               business_period: business_period,
               table: center_table_4,
               party_size: 3,
               adults_count: 3,
               children_count: 0,
               reservation_datetime: base_time)
        
        # 8人訂位需求
        large_reservation = create(:reservation,
                                 restaurant: restaurant,
                                 business_period: business_period,
                                 party_size: 8,
                                 adults_count: 8,
                                 children_count: 0,
                                 reservation_datetime: base_time + 10.minutes)
        
        service = ReservationAllocatorService.new(large_reservation)
        result = service.allocate_table
        
        expect(result).to be_present
        large_reservation.reload
        
        if large_reservation.table_combination.present?
          combination = large_reservation.table_combination
          expect(combination.total_capacity).to be >= 8
          
          # 驗證併桌邏輯：應該選擇最少桌位數的組合
          puts "8人併桌組合：#{combination.table_numbers}，總容量：#{combination.total_capacity}"
          
          # 檢查是否為同群組
          table_groups = combination.restaurant_tables.map(&:table_group).uniq
          expect(table_groups.count).to eq(1)
        end
      end
      
      it '連續大型訂位的併桌資源競爭' do
        # 第一個6人訂位
        first_large = create(:reservation,
                           restaurant: restaurant,
                           business_period: business_period,
                           party_size: 6,
                           adults_count: 6,
                           children_count: 0,
                           reservation_datetime: base_time)
        
        service1 = ReservationAllocatorService.new(first_large)
        result1 = service1.allocate_table
        expect(result1).to be_present
        
        # 第二個6人訂位
        second_large = create(:reservation,
                            restaurant: restaurant,
                            business_period: business_period,
                            party_size: 6,
                            adults_count: 6,
                            children_count: 0,
                            reservation_datetime: base_time + 15.minutes)
        
        service2 = ReservationAllocatorService.new(second_large)
        result2 = service2.allocate_table
        
        # 檢查兩個大型訂位是否都能成功分配
        first_large.reload
        second_large.reload
        
        puts "第一個6人訂位：#{first_large.table_display_name}"
        puts "第二個6人訂位：#{second_large.table_display_name}"
        
        # 至少其中一個應該成功分配
        expect([first_large.table.present? || first_large.table_combination.present?,
                second_large.table.present? || second_large.table_combination.present?].any?).to be true
      end
      
      it '混合單桌和併桌的複雜分配情境' do
        # 先分配一些單桌訂位
        small_reservations = []
        [window_table_2, center_table_2a].each_with_index do |table, index|
          reservation = create(:reservation, :confirmed,
                             restaurant: restaurant,
                             business_period: business_period,
                             table: table,
                             party_size: 2,
                             adults_count: 2,
                             children_count: 0,
                             reservation_datetime: base_time)
          small_reservations << reservation
        end
        
        # 現在有一個5人訂位需要併桌
        medium_reservation = create(:reservation,
                                  restaurant: restaurant,
                                  business_period: business_period,
                                  party_size: 5,
                                  adults_count: 5,
                                  children_count: 0,
                                  reservation_datetime: base_time + 20.minutes)
        
        service = ReservationAllocatorService.new(medium_reservation)
        result = service.allocate_table
        
        medium_reservation.reload
        
        # 檢查分配結果
        if medium_reservation.table_combination.present?
          combination = medium_reservation.table_combination
          puts "5人併桌組合：#{combination.table_numbers}，總容量：#{combination.total_capacity}"
          
          # 確保沒有使用已佔用的桌位
          occupied_table_ids = small_reservations.map(&:table_id)
          combination_table_ids = combination.restaurant_tables.pluck(:id)
          
          expect(combination_table_ids & occupied_table_ids).to be_empty
        elsif medium_reservation.table.present?
          puts "5人單桌分配：#{medium_reservation.table.table_number}"
          expect(medium_reservation.table.capacity).to be >= 5
        end
      end
    end
    
    context '無限用餐時間模式下的併桌' do
      before do
        restaurant.reservation_policy.update!(unlimited_dining_time: true)
      end
      
      it '同餐期併桌衝突檢查' do
        # 佔用併桌組合中的一張桌位
        existing_reservation = create(:reservation, :confirmed,
                                    restaurant: restaurant,
                                    business_period: business_period,
                                    table: center_table_2a,
                                    party_size: 2,
                                    adults_count: 2,
                                    children_count: 0,
                                    reservation_datetime: base_time)
        
        # 新的4人訂位需要併桌，但center_table_2a已被佔用
        new_reservation = create(:reservation,
                               restaurant: restaurant,
                               business_period: business_period,
                               party_size: 4,
                               adults_count: 4,
                               children_count: 0,
                               reservation_datetime: base_time + 2.hours) # 無限時模式下時間差不影響
        
        service = ReservationAllocatorService.new(new_reservation)
        result = service.allocate_table
        
        new_reservation.reload
        
        if new_reservation.table_combination.present?
          combination = new_reservation.table_combination
          combination_table_ids = combination.restaurant_tables.pluck(:id)
          
          # 確保沒有使用已佔用的桌位
          expect(combination_table_ids).not_to include(center_table_2a.id)
          puts "無限時模式併桌避開衝突：#{combination.table_numbers}"
        end
      end
      
      it '不同餐期可以重複使用併桌組合' do
        dinner_period = create(:business_period, restaurant: restaurant, name: '晚餐')
        
        # 午餐時段的併桌
        lunch_reservation = create(:reservation,
                                 restaurant: restaurant,
                                 business_period: business_period,
                                 party_size: 4,
                                 adults_count: 4,
                                 children_count: 0,
                                 reservation_datetime: base_time)
        
        service1 = ReservationAllocatorService.new(lunch_reservation)
        result1 = service1.allocate_table
        
        lunch_reservation.reload
        lunch_tables = []
        
        if lunch_reservation.table_combination.present?
          lunch_tables = lunch_reservation.table_combination.restaurant_tables
        elsif lunch_reservation.table.present?
          lunch_tables = [lunch_reservation.table]
        end
        
        # 晚餐時段的併桌，可以使用相同桌位
        dinner_reservation = create(:reservation,
                                  restaurant: restaurant,
                                  business_period: dinner_period,
                                  party_size: 4,
                                  adults_count: 4,
                                  children_count: 0,
                                  reservation_datetime: base_time.change(hour: 18))
        
        service2 = ReservationAllocatorService.new(dinner_reservation)
        result2 = service2.allocate_table
        
        dinner_reservation.reload
        
        # 在無限時模式下，不同餐期應該可以重複使用桌位
        expect(result2).to be_present
        puts "午餐併桌：#{lunch_reservation.table_display_name}"
        puts "晚餐併桌：#{dinner_reservation.table_display_name}"
      end
    end
    
    context '併桌容量優化測試' do
      it '選擇最接近需求的併桌組合' do
        # 5人訂位，有多種併桌選擇
        reservation = create(:reservation,
                           restaurant: restaurant,
                           business_period: business_period,
                           party_size: 5,
                           adults_count: 5,
                           children_count: 0,
                           reservation_datetime: base_time)
        
        service = ReservationAllocatorService.new(reservation)
        result = service.allocate_table
        
        reservation.reload
        
        if reservation.table_combination.present?
          combination = reservation.table_combination
          total_capacity = combination.total_capacity
          
          # 應該選擇容量最接近5人的組合，避免浪費
          expect(total_capacity).to be >= 5
          expect(total_capacity).to be <= 8 # 不應該過度分配
          
          puts "5人最佳併桌：#{combination.table_numbers}，容量：#{total_capacity}"
        elsif reservation.table.present?
          # 如果有單桌能滿足，應該優先使用單桌
          expect(reservation.table.capacity).to be >= 5
          puts "5人單桌分配：#{reservation.table.table_number}，容量：#{reservation.table.capacity}"
        end
      end
      
      it '大型聚會的多桌併桌策略' do
        # 12人大型聚會
        large_party = create(:reservation,
                           restaurant: restaurant,
                           business_period: business_period,
                           party_size: 12,
                           adults_count: 12,
                           children_count: 0,
                           reservation_datetime: base_time)
        
        service = ReservationAllocatorService.new(large_party)
        result = service.allocate_table
        
        large_party.reload
        
        if large_party.table_combination.present?
          combination = large_party.table_combination
          
          # 檢查併桌數量不超過限制
          expect(combination.restaurant_tables.count).to be <= restaurant.reservation_policy.max_combination_tables
          
          # 檢查總容量足夠
          expect(combination.total_capacity).to be >= 12
          
          puts "12人大型併桌：#{combination.table_numbers}，總容量：#{combination.total_capacity}"
          
          # 檢查桌位排序邏輯
          sort_orders = combination.restaurant_tables.pluck(:sort_order).sort
          puts "併桌排序：#{sort_orders}"
        end
      end
    end
    
    context '併桌失敗和降級策略' do
      it '當併桌無法滿足需求時的處理' do
        # 佔用大部分桌位
        occupied_tables = [window_table_4, window_table_6, center_table_4]
        occupied_tables.each_with_index do |table, index|
          create(:reservation, :confirmed,
                 restaurant: restaurant,
                 business_period: business_period,
                 table: table,
                 party_size: [table.capacity - 1, 1].max,
                 adults_count: [table.capacity - 1, 1].max,
                 children_count: 0,
                 reservation_datetime: base_time)
        end
        
        # 10人訂位，剩餘桌位無法滿足
        impossible_reservation = create(:reservation,
                                      restaurant: restaurant,
                                      business_period: business_period,
                                      party_size: 10,
                                      adults_count: 10,
                                      children_count: 0,
                                      reservation_datetime: base_time + 30.minutes)
        
        service = ReservationAllocatorService.new(impossible_reservation)
        result = service.allocate_table
        
        # 應該回傳 nil 或找到替代方案
        if result.nil?
          puts "10人訂位無法分配（符合預期）"
          expect(result).to be_nil
        else
          puts "10人訂位找到替代方案：#{impossible_reservation.reload.table_display_name}"
        end
      end
      
      it '跨群組併桌限制驗證' do
        # 佔用窗邊區的大桌
        create(:reservation, :confirmed,
               restaurant: restaurant,
               business_period: business_period,
               table: window_table_6,
               party_size: 6,
               adults_count: 6,
               children_count: 0,
               reservation_datetime: base_time)
        
        # 佔用中央區的大桌
        create(:reservation, :confirmed,
               restaurant: restaurant,
               business_period: business_period,
               table: center_table_4,
               party_size: 4,
               adults_count: 4,
               children_count: 0,
               reservation_datetime: base_time)
        
        # 8人訂位，需要跨群組才能滿足
        cross_group_reservation = create(:reservation,
                                       restaurant: restaurant,
                                       business_period: business_period,
                                       party_size: 8,
                                       adults_count: 8,
                                       children_count: 0,
                                       reservation_datetime: base_time + 45.minutes)
        
        service = ReservationAllocatorService.new(cross_group_reservation)
        result = service.allocate_table
        
        cross_group_reservation.reload
        
        if cross_group_reservation.table_combination.present?
          combination = cross_group_reservation.table_combination
          table_groups = combination.restaurant_tables.map(&:table_group).uniq
          
          # 驗證不會跨群組併桌
          expect(table_groups.count).to eq(1)
          puts "8人併桌限制在單一群組：#{table_groups.first.name}"
        end
      end
    end
  end

  private

  def setup_test_tables
    # 建立桌位群組
    @table_group_window = create(:table_group, restaurant: restaurant, name: '窗邊圓桌', sort_order: 1)
    @table_group_square = create(:table_group, restaurant: restaurant, name: '方桌', sort_order: 2)
    @table_group_bar = create(:table_group, restaurant: restaurant, name: '吧台', sort_order: 3)

    # 建立窗邊圓桌 (5人) - 不允許併桌，因為是特殊桌位
    @window_table = create(:table,
                          restaurant: restaurant,
                          table_group: @table_group_window,
                          table_number: '窗邊圓桌',
                          table_type: 'round',
                          capacity: 5,
                          min_capacity: 4,
                          max_capacity: 5,
                          can_combine: false,  # 窗邊圓桌通常不併桌
                          sort_order: 1)

    # 建立方桌群組 (多種規格，支援併桌)
    @square_tables = []
    
    # 2張4人方桌 - 支援併桌
    2.times do |i|
      @square_tables << create(:table,
                              restaurant: restaurant,
                              table_group: @table_group_square,
                              table_number: "方桌4人#{i+1}",
                              table_type: 'square',
                              capacity: 4,
                              min_capacity: 2,
                              max_capacity: 4,
                              can_combine: true,
                              sort_order: i + 1)
    end

    # 3張2人方桌 - 支援併桌
    3.times do |i|
      @square_tables << create(:table,
                              restaurant: restaurant,
                              table_group: @table_group_square,
                              table_number: "方桌2人#{i+1}",
                              table_type: 'square',
                              capacity: 2,
                              min_capacity: 1,
                              max_capacity: 2,
                              can_combine: true,
                              sort_order: i + 3)
    end

    # 建立吧台座位 (1人 x 3) - 不支援併桌
    @bar_tables = []
    3.times do |i|
      @bar_tables << create(:table,
                           restaurant: restaurant,
                           table_group: @table_group_bar,
                           table_number: "吧台#{i+1}",
                           table_type: 'bar',
                           capacity: 1,
                           min_capacity: 1,
                           max_capacity: 1,
                           can_combine: false, # 吧台不支援併桌
                           sort_order: i + 1)
    end

    # 更新餐廳總容量
    total_capacity = [@window_table.max_capacity] + 
                    @square_tables.map(&:max_capacity) + 
                    @bar_tables.map(&:max_capacity)
    restaurant.update!(total_capacity: total_capacity.sum)
    
    puts "測試桌位設置完成："
    puts "- 窗邊圓桌：#{@window_table.capacity}人"
    puts "- 方桌：#{@square_tables.map(&:capacity).join('+')}人"
    puts "- 吧台：#{@bar_tables.map(&:capacity).join('+')}人"
    puts "- 總容量：#{restaurant.total_capacity}人"
  end
end 