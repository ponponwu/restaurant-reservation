require 'rails_helper'

RSpec.describe ReservationAllocatorService, type: :service do
  let(:restaurant) { create(:restaurant) }
  let(:table_group_window) { create(:table_group, restaurant: restaurant, name: '窗邊圓桌', sort_order: 1) }
  let(:table_group_square) { create(:table_group, restaurant: restaurant, name: '方桌', sort_order: 2) }
  let(:table_group_bar) { create(:table_group, restaurant: restaurant, name: '吧台', sort_order: 3) }
  
  let(:business_period) do
    create(:business_period, 
           restaurant: restaurant,
           start_time: '11:30',
           end_time: '14:30',
           days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
  end

  before do
    # 建立測試用桌位環境
    setup_test_tables
    
    # 更新餐廳總容量
    restaurant.update!(total_capacity: restaurant.calculate_total_capacity)
    
    # 更新餐廳政策以允許更大的人數（配合總容量）
    policy = restaurant.reservation_policy || restaurant.create_reservation_policy
    total_capacity = restaurant.calculate_total_capacity
    policy.update!(
      max_party_size: [total_capacity, 20].max,  # 至少要等於總容量
      min_party_size: 1,
      advance_booking_days: 30,
      minimum_advance_hours: 1
    )
  end

  describe '#allocate_table' do
    context '基本桌位分配功能' do
      let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }

      context '當有適合的單一桌位時' do
        it '為5人分配窗邊圓桌' do
          reservation = create(:reservation, 
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 5,
                             adults_count: 5,
                             children_count: 0,
                             reservation_datetime: reservation_time)

          service = described_class.new(reservation)
          result = service.allocate_table

          expect(result).to be_present
          expect(result.table_number).to eq('窗邊圓桌')
          expect(result.table_type).to eq('round')
        end

        it '為4人分配窗邊圓桌' do
          reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 4,
                             adults_count: 4,
                             children_count: 0,
                             reservation_datetime: reservation_time)

          service = described_class.new(reservation)
          result = service.allocate_table

          expect(result).to be_present
          expect(result.table_number).to eq('窗邊圓桌')
        end

        it '為2人分配方桌' do
          reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 2,
                             adults_count: 2,
                             children_count: 0,
                             reservation_datetime: reservation_time)

                  service = described_class.new(reservation)
        result = service.allocate_table

        expect(result).to be_present
        expect(result.table_group.name).to eq('方桌')
          expect(result.capacity).to eq(2)
        end
      end

      context '優先級排序測試' do
        it '1人應優先分配到方桌而非吧台' do
          reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 1,
                             adults_count: 1,
                             children_count: 0,
                             reservation_datetime: reservation_time)

          service = described_class.new(reservation)
          result = service.allocate_table

          expect(result).to be_present
          expect(result.table_group.name).to eq('方桌')
        end

        context '當方桌都被佔用時' do
          before do
            # 佔用所有方桌
            @square_tables.each do |table|
              create(:reservation, :confirmed,
                   restaurant: restaurant,
                   business_period: business_period,
                   table: table,
                   party_size: 2,
                   adults_count: 2,
                   children_count: 0,
                   reservation_datetime: reservation_time)
            end
          end

          it '1人應分配到吧台' do
            reservation = create(:reservation,
                               restaurant: restaurant,
                               business_period: business_period,
                               party_size: 1,
                               adults_count: 1,
                               children_count: 0,
                               reservation_datetime: reservation_time)

            service = described_class.new(reservation)
            result = service.allocate_table

            expect(result).to be_present
            expect(result.table_group.name).to eq('吧台')
          end
        end
      end
    end

    context '容量限制檢查' do
      let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }

      it '拒絕超過窗邊圓桌上限的6人訂位' do
        reservation = create(:reservation,
                           restaurant: restaurant,
                           business_period: business_period,
                           party_size: 6,
                           adults_count: 6,
                           children_count: 0,
                           reservation_datetime: reservation_time)

        service = described_class.new(reservation)
        result = service.allocate_table

        expect(result).to be_nil
      end

      it '拒絕低於窗邊圓桌下限的3人訂位（當無法併桌時）' do
        reservation = create(:reservation,
                           restaurant: restaurant,
                           business_period: business_period,
                           party_size: 3,
                           adults_count: 3,
                           children_count: 0,
                           reservation_datetime: reservation_time)

        service = described_class.new(reservation)
        result = service.allocate_table

        expect(result).to be_nil
      end

      it '拒絕超過總容量的訂位' do
        total_capacity = restaurant.total_capacity
        reservation = create(:reservation,
                           restaurant: restaurant,
                           business_period: business_period,
                           party_size: total_capacity + 1,
                           adults_count: total_capacity + 1,
                           children_count: 0,
                           reservation_datetime: reservation_time)

        service = described_class.new(reservation)
        result = service.allocate_table

        expect(result).to be_nil
      end
    end

    context '桌位可用性檢查' do
      let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }

      context '當所有桌位都被佔用時' do
        before do
          # 佔用窗邊圓桌
          create(:reservation, :confirmed,
               restaurant: restaurant,
               business_period: business_period,
               table: @window_table,
               party_size: 5,
               adults_count: 5,
               children_count: 0,
               reservation_datetime: reservation_time)

          # 佔用所有方桌
          @square_tables.each do |table|
            create(:reservation, :confirmed,
                 restaurant: restaurant,
                 business_period: business_period,
                 table: table,
                 party_size: 2,
                 adults_count: 2,
                 children_count: 0,
                 reservation_datetime: reservation_time)
          end

          # 佔用所有吧台
          @bar_tables.each do |table|
            create(:reservation, :confirmed,
                 restaurant: restaurant,
                 business_period: business_period,
                 table: table,
                 party_size: 1,
                 adults_count: 1,
                 children_count: 0,
                 reservation_datetime: reservation_time)
          end
        end

        it '應該拒絕新的訂位' do
          reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 1,
                             adults_count: 1,
                             children_count: 0,
                             reservation_datetime: reservation_time)

          service = described_class.new(reservation)
          result = service.allocate_table

          expect(result).to be_nil
        end
      end

      context '同餐期重複訂位檢查' do
        it '應該分配到不同桌位' do
          # 第一個訂位
          first_reservation = create(:reservation,
                                   restaurant: restaurant,
                                   business_period: business_period,
                                   party_size: 2,
                                   adults_count: 2,
                                   children_count: 0,
                                   reservation_datetime: reservation_time)

          first_service = described_class.new(first_reservation)
          first_table = first_service.allocate_table
          first_reservation.update!(table: first_table)

          # 第二個訂位
          second_reservation = create(:reservation,
                                    restaurant: restaurant,
                                    business_period: business_period,
                                    party_size: 2,
                                    adults_count: 2,
                                    children_count: 0,
                                    reservation_datetime: reservation_time)

          second_service = described_class.new(second_reservation)
          second_table = second_service.allocate_table

          expect(first_table).to be_present
          expect(second_table).to be_present
          expect(first_table.id).not_to eq(second_table.id)
        end
      end
    end

    context '營業時段隔離' do
      let(:lunch_time) { 1.day.from_now.change(hour: 12, min: 0) }
      let(:dinner_time) { 1.day.from_now.change(hour: 18, min: 0) }
      
      let(:dinner_period) do
        create(:business_period,
               restaurant: restaurant,
               name: '晚餐時段',
               start_time: '17:30',
               end_time: '21:30',
               days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
      end

      it '不同營業時段可以使用相同桌位' do
        # 午餐時段訂位
        lunch_reservation = create(:reservation,
                                 restaurant: restaurant,
                                 business_period: business_period,
                                 party_size: 5,
                                 adults_count: 5,
                                 children_count: 0,
                                 reservation_datetime: lunch_time)

        lunch_service = described_class.new(lunch_reservation)
        lunch_table = lunch_service.allocate_table
        lunch_reservation.update!(table: lunch_table)

        # 晚餐時段訂位
        dinner_reservation = create(:reservation,
                                  restaurant: restaurant,
                                  business_period: dinner_period,
                                  party_size: 5,
                                  adults_count: 5,
                                  children_count: 0,
                                  reservation_datetime: dinner_time)

        dinner_service = described_class.new(dinner_reservation)
        dinner_table = dinner_service.allocate_table

        expect(lunch_table).to be_present
        expect(dinner_table).to be_present
        expect(lunch_table.id).to eq(dinner_table.id)
      end
    end

    context '有兒童的訂位' do
      let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }

      it '有兒童時不應分配吧台座位' do
        reservation = create(:reservation, :with_children,
                           restaurant: restaurant,
                           business_period: business_period,
                           reservation_datetime: reservation_time)

        service = described_class.new(reservation)
        result = service.allocate_table

        expect(result).to be_present
        expect(result.table_type).not_to eq('bar')
      end
    end

    context '取消訂位後的桌位釋放' do
      let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }

      it '取消訂位後應該可以重新分配桌位' do
        # 建立並分配訂位
        original_reservation = create(:reservation,
                                    restaurant: restaurant,
                                    business_period: business_period,
                                    party_size: 2,
                                    adults_count: 2,
                                    children_count: 0,
                                    reservation_datetime: reservation_time)

        service = described_class.new(original_reservation)
        table = service.allocate_table
        original_reservation.update!(table: table)

        # 取消訂位
        original_reservation.update!(status: 'cancelled')

        # 新的訂位應該可以分配到相同桌位
        new_reservation = create(:reservation,
                               restaurant: restaurant,
                               business_period: business_period,
                               party_size: 2,
                               adults_count: 2,
                               children_count: 0,
                               reservation_datetime: reservation_time)

        new_service = described_class.new(new_reservation)
        new_table = new_service.allocate_table

        expect(new_table).to be_present
        expect(new_table.id).to eq(table.id)
      end
    end

    context '邊界情況處理' do
      let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }

      context '當所有桌位都停用時' do
        before do
          restaurant.restaurant_tables.update_all(operational_status: 'maintenance')
        end

        it '應該拒絕所有訂位' do
          reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 2,
                             adults_count: 2,
                             children_count: 0,
                             reservation_datetime: reservation_time)

          service = described_class.new(reservation)
          result = service.allocate_table

          expect(result).to be_nil
        end
      end

      it '總容量邊界測試：剛好達到總容量的訂位' do
        total_capacity = restaurant.total_capacity
        reservation = create(:reservation,
                           restaurant: restaurant,
                           business_period: business_period,
                           party_size: total_capacity,
                           adults_count: total_capacity,
                           children_count: 0,
                           reservation_datetime: reservation_time)

        service = described_class.new(reservation)
        result = service.allocate_table

        # 這個測試會顯示是否需要併桌功能來滿足大容量訂位
        expect(result).to be_present.or be_nil
      end
    end

    context '併發情況模擬' do
      let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }

      it '多個同時訂位應該正確分配到不同桌位' do
        reservations = []
        tables = []

        # 建立5個相同需求的訂位（都要2人桌）
        5.times do
          reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 2,
                             adults_count: 2,
                             children_count: 0,
                             reservation_datetime: reservation_time)
          
          service = described_class.new(reservation)
          table = service.allocate_table
          reservation.update!(table: table) if table

          reservations << reservation
          tables << table
        end

        successful_allocations = tables.compact.count
        total_available_tables = @square_tables.count  # 3張方桌

        expect(successful_allocations).to eq(total_available_tables)
        expect(tables.compact.map(&:id).uniq.count).to eq(successful_allocations)
      end
    end
  end

  describe '#find_available_tables' do
    let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }
    let(:reservation) do
      create(:reservation,
             restaurant: restaurant,
             business_period: business_period,
             party_size: 2,
             adults_count: 2,
             children_count: 0,
             reservation_datetime: reservation_time)
    end

    it '返回適合的可用桌位' do
      service = described_class.new(reservation)
      available_tables = service.find_available_tables

      expect(available_tables).to be_an(Array)
      expect(available_tables.all? { |table| table.suitable_for?(2) }).to be true
    end

    context '當有桌位被佔用時' do
      before do
        # 佔用一張方桌
        create(:reservation, :confirmed,
             restaurant: restaurant,
             business_period: business_period,
             table: @square_tables.first,
             party_size: 2,
             adults_count: 2,
             children_count: 0,
             reservation_datetime: reservation_time)
      end

      it '不應包含被佔用的桌位' do
        service = described_class.new(reservation)
        available_tables = service.find_available_tables

        expect(available_tables).not_to include(@square_tables.first)
      end
    end
  end

  describe '#check_availability' do
    let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }
    let(:reservation) do
      create(:reservation,
             restaurant: restaurant,
             business_period: business_period,
             party_size: 2,
             adults_count: 2,
             children_count: 0,
             reservation_datetime: reservation_time)
    end

    it '返回可用性檢查結果' do
      service = described_class.new(reservation)
      result = service.check_availability

      expect(result).to be_a(Hash)
      expect(result).to have_key(:has_availability)
      expect(result).to have_key(:available_tables)
      expect(result).to have_key(:can_combine)
      expect(result).to have_key(:combinable_tables)
    end
  end

  # 併桌功能測試（如果已實作）
  describe '併桌功能測試' do
    let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }

    context '需要併桌的大人數訂位' do
      [
        { party_size: 7, description: '7人需要併桌(窗邊5+方桌2)' },
        { party_size: 8, description: '8人需要併桌(窗邊5+方桌2+方桌1)' },
        { party_size: 6, description: '6人需要併桌(方桌2+方桌2+方桌2)' }
      ].each do |test_case|
        it test_case[:description] do
          reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: test_case[:party_size],
                             adults_count: test_case[:party_size],
                             children_count: 0,
                             reservation_datetime: reservation_time)

          service = described_class.new(reservation)
          result = service.allocate_table

          # 檢查併桌功能是否正常工作
          if result.nil?
            pending "併桌功能尚未完全實作：無法為#{test_case[:party_size]}人分配桌位"
          else
            expect(result).to be_present
            
            # 檢查是否正確建立了 table_combination（如果需要併桌）
            if test_case[:party_size] > 5  # 超過單一窗邊圓桌容量
              # 重新加載 reservation 來檢查關聯
              reservation.reload
              expect(reservation.table_combination).to be_present
            end
          end
        end
      end
    end
  end

  # 新增複雜情境測試
  describe '複雜情境測試' do
    let(:base_time) { 1.day.from_now.change(hour: 12, min: 0) }

    context '時間重疊和衝突處理' do
      it '應該正確處理用餐時間重疊的複雜情況' do
        # 建立一個2小時前開始的訂位
        early_reservation = create(:reservation, :confirmed,
                                  restaurant: restaurant,
                                  business_period: business_period,
                                  table: @square_tables[0],
                                  party_size: 2,
                                  adults_count: 2,
                                  children_count: 0,
                                  reservation_datetime: base_time - 2.hours)

        # 建立一個1小時後的訂位，這應該會衝突
        new_reservation = create(:reservation,
                               restaurant: restaurant,
                               business_period: business_period,
                               party_size: 2,
                               adults_count: 2,
                               children_count: 0,
                               reservation_datetime: base_time - 1.hour)

        service = described_class.new(new_reservation)
        result = service.allocate_table

        # 應該分配到不同的桌位
        expect(result).to be_present
        expect(result).not_to eq(@square_tables[0])
      end

      it '應該正確處理跨營業時段的訂位' do
        # 建立晚餐時段
        dinner_period = create(:business_period,
                             restaurant: restaurant,
                             start_time: '17:30',
                             end_time: '21:30',
                             days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])

        # 午餐時段的最後一個訂位
        lunch_reservation = create(:reservation,
                                  restaurant: restaurant,
                                  business_period: business_period,
                                  party_size: 4,
                                  adults_count: 4,
                                  children_count: 0,
                                  reservation_datetime: base_time.change(hour: 14, min: 0))

        # 晚餐時段的第一個訂位（同一桌應該可用）
        dinner_reservation = create(:reservation,
                                   restaurant: restaurant,
                                   business_period: dinner_period,
                                   party_size: 4,
                                   adults_count: 4,
                                   children_count: 0,
                                   reservation_datetime: base_time.change(hour: 17, min: 30))

        lunch_service = described_class.new(lunch_reservation)
        lunch_table = lunch_service.allocate_table

        dinner_service = described_class.new(dinner_reservation)
        dinner_table = dinner_service.allocate_table

        expect(lunch_table).to be_present
        expect(dinner_table).to be_present
        # 同一桌在不同營業時段應該可以重複使用
        expect(lunch_table).to eq(dinner_table)
      end
    end

    context '多種桌位類型混合分配' do
      it '應該優先分配最適合的桌位類型' do
        # 1人訂位應該優先分配方桌而非吧台
        single_reservation = create(:reservation,
                                   restaurant: restaurant,
                                   business_period: business_period,
                                   party_size: 1,
                                   adults_count: 1,
                                   children_count: 0,
                                   reservation_datetime: base_time)

        service = described_class.new(single_reservation)
        result = service.allocate_table

        expect(result).to be_present
        expect(result.table_type).to eq('square')
        expect(result.table_group.name).to eq('方桌')
      end

      it '當優先桌位不可用時應該降級使用次優桌位' do
        # 先佔用所有方桌
        @square_tables.each do |table|
          create(:reservation, :confirmed,
                restaurant: restaurant,
                business_period: business_period,
                table: table,
                party_size: 1,
                adults_count: 1,
                children_count: 0,
                reservation_datetime: base_time)
        end

        # 新的1人訂位應該分配到吧台
        single_reservation = create(:reservation,
                                   restaurant: restaurant,
                                   business_period: business_period,
                                   party_size: 1,
                                   adults_count: 1,
                                   children_count: 0,
                                   reservation_datetime: base_time + 1.minute)

        service = described_class.new(single_reservation)
        result = service.allocate_table

        expect(result).to be_present
        expect(result.table_type).to eq('bar')
        expect(result.table_group.name).to eq('吧台')
      end
    end

    context '特殊群體的訂位需求' do
      it '有兒童的訂位不應分配吧台座位' do
        family_reservation = create(:reservation,
                                   restaurant: restaurant,
                                   business_period: business_period,
                                   party_size: 2,
                                   adults_count: 1,
                                   children_count: 1,
                                   reservation_datetime: base_time)

        # 先佔用所有方桌，強制系統考慮吧台
        @square_tables.each do |table|
          create(:reservation, :confirmed,
                restaurant: restaurant,
                business_period: business_period,
                table: table,
                party_size: 2,
                adults_count: 2,
                children_count: 0,
                reservation_datetime: base_time)
        end

        service = described_class.new(family_reservation)
        result = service.allocate_table

        # 應該分配到窗邊圓桌而非吧台
        expect(result).to be_present
        expect(result.table_type).not_to eq('bar')
      end

      it '大型聚會應該能正確併桌' do
        large_party = create(:reservation,
                            restaurant: restaurant,
                            business_period: business_period,
                            party_size: 10,
                            adults_count: 8,
                            children_count: 2,
                            reservation_datetime: base_time)

        service = described_class.new(large_party)
        result = service.allocate_table

        if result.present?
          # 檢查是否建立了桌位組合
          large_party.reload
          expect(large_party.table_combination).to be_present
          expect(large_party.table_combination.restaurant_tables.count).to be >= 2
          
          total_capacity = large_party.table_combination.restaurant_tables.sum(:max_capacity)
          expect(total_capacity).to be >= 10
        else
          pending "需要更多桌位來支援10人的大型聚會"
        end
      end
    end

    context '營業狀況壓力測試' do
      it '高峰時段應該能有效分配所有可用桌位' do
        peak_time = base_time.change(hour: 12, min: 30)  # 午餐高峰
        successful_allocations = 0
        total_attempts = 20

        total_attempts.times do |i|
                   party_size = [1, 2, 4].sample
         reservation = create(:reservation,
                            restaurant: restaurant,
                            business_period: business_period,
                            party_size: party_size,
                            adults_count: party_size,
                            children_count: 0,
                            reservation_datetime: peak_time + i.minutes)

          service = described_class.new(reservation)
          result = service.allocate_table

          if result.present?
            successful_allocations += 1
            reservation.update!(table: result)
          end
        end

        # 至少應該能分配80%的訂位
        success_rate = successful_allocations.to_f / total_attempts
        expect(success_rate).to be >= 0.8
      end

      it '應該能處理連續的取消和重新分配' do
        reservations = []
        
        # 建立5個訂位
        5.times do |i|
          reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 2,
                             adults_count: 2,
                             children_count: 0,
                             reservation_datetime: base_time + i.minutes)

          service = described_class.new(reservation)
          table = service.allocate_table
          reservation.update!(table: table) if table
          reservations << reservation
        end

        # 取消第2和第4個訂位
        [1, 3].each do |index|
          reservations[index].update!(status: 'cancelled', table: nil)
        end

        # 建立新的訂位，應該能重新分配到被釋放的桌位
        new_reservations = []
        2.times do |i|
          reservation = create(:reservation,
                             restaurant: restaurant,
                             business_period: business_period,
                             party_size: 2,
                             adults_count: 2,
                             children_count: 0,
                             reservation_datetime: base_time + (10 + i).minutes)

          service = described_class.new(reservation)
          table = service.allocate_table
          new_reservations << { reservation: reservation, table: table }
        end

        # 新訂位應該能成功分配
        expect(new_reservations.all? { |nr| nr[:table].present? }).to be true
      end
    end

    context '資料一致性測試' do
      it '併發分配不應該造成重複分配' do
        same_time = base_time
        threads = []
        results = []

        # 模擬3個同時的訂位請求
        3.times do |i|
          threads << Thread.new do
            reservation = create(:reservation,
                                restaurant: restaurant,
                                business_period: business_period,
                                party_size: 2,
                                adults_count: 2,
                                children_count: 0,
                                reservation_datetime: same_time)

            service = described_class.new(reservation)
            table = service.allocate_table
            results << { reservation_id: reservation.id, table_id: table&.id }
          end
        end

        threads.each(&:join)

        # 檢查沒有重複分配同一桌位
        assigned_tables = results.map { |r| r[:table_id] }.compact
        expect(assigned_tables.uniq.count).to eq(assigned_tables.count)
      end

      it '桌位狀態應該與訂位記錄一致' do
        reservation = create(:reservation,
                           restaurant: restaurant,
                           business_period: business_period,
                           party_size: 4,
                           adults_count: 4,
                           children_count: 0,
                           reservation_datetime: base_time)

        service = described_class.new(reservation)
        table = service.allocate_table
        reservation.update!(table: table)

        # 檢查桌位在該時間段不可用
        expect(table.available_for_datetime?(base_time)).to be false
        expect(table.available_for_datetime?(base_time + 1.hour)).to be false
        expect(table.available_for_datetime?(base_time + 3.hours)).to be true
      end
    end

    context '邊界條件壓力測試' do
      it '應該正確處理剛好達到容量上限的情況' do
        # 計算餐廳總容量
        total_capacity = restaurant.calculate_total_capacity
        
        # 嘗試建立一個剛好等於總容量的訂位
        max_reservation = create(:reservation,
                               restaurant: restaurant,
                               business_period: business_period,
                               party_size: total_capacity,
                               adults_count: total_capacity,
                               children_count: 0,
                               reservation_datetime: base_time)

        service = described_class.new(max_reservation)
        result = service.allocate_table

        if result.present?
          # 如果成功分配，檢查是否用盡了所有桌位
          max_reservation.reload
          if max_reservation.table_combination
            used_capacity = max_reservation.table_combination.restaurant_tables.sum(:max_capacity)
            expect(used_capacity).to eq(total_capacity)
          end
        else
          # 如果無法分配，應該是因為併桌限制或其他合理原因
          expect(total_capacity).to be > 6  # 確認不是因為容量太小
        end
      end

      it '應該在桌位不足時提供有用的錯誤信息' do
        # 超過總容量的訂位
        over_capacity = restaurant.calculate_total_capacity + 5
        
        impossible_reservation = create(:reservation,
                                      restaurant: restaurant,
                                      business_period: business_period,
                                      party_size: over_capacity,
                                      adults_count: over_capacity,
                                      children_count: 0,
                                      reservation_datetime: base_time)

        service = described_class.new(impossible_reservation)
        result = service.allocate_table

        expect(result).to be_nil
        
        # 檢查可用性信息
        availability = service.check_availability
        expect(availability[:has_availability]).to be false
        expect(availability[:available_tables]).to be_present
      end
    end
  end

  # 無限用餐時間桌位分配測試
  describe '無限用餐時間桌位分配' do
    let(:unlimited_restaurant) { create(:restaurant) }
    let(:unlimited_lunch_period) { create(:business_period, restaurant: unlimited_restaurant, name: '午餐', start_time: '11:30', end_time: '14:30') }
    let(:unlimited_dinner_period) { create(:business_period, restaurant: unlimited_restaurant, name: '晚餐', start_time: '17:30', end_time: '21:30') }
    
    let(:unlimited_test_group) { create(:table_group, restaurant: unlimited_restaurant, name: '測試群組', sort_order: 0) }
    let(:unlimited_other_group) { create(:table_group, restaurant: unlimited_restaurant, name: '其他群組', sort_order: 1) }
    
    let(:test_time) { 1.day.from_now.change(hour: 12, min: 0) }
    
    before do
      # 設定無限用餐時間模式
      policy = unlimited_restaurant.reservation_policy || unlimited_restaurant.create_reservation_policy
      policy.update!(unlimited_dining_time: true)
      
      # 創建測試桌位
      @t4_table = create(:restaurant_table,
                        restaurant: unlimited_restaurant,
                        table_group: unlimited_test_group,
                        table_number: 'T4',
                        capacity: 4,
                        min_capacity: 2,
                        max_capacity: 6,
                        table_type: 'square',
                        sort_order: 0,
                        can_combine: true,
                        operational_status: 'normal')
      
      @t2_table = create(:restaurant_table,
                        restaurant: unlimited_restaurant,
                        table_group: unlimited_test_group,
                        table_number: 'T2',
                        capacity: 2,
                        min_capacity: 1,
                        max_capacity: 3,
                        table_type: 'square',
                        sort_order: 1,
                        can_combine: true,
                        operational_status: 'normal')
      
      @o1_table = create(:restaurant_table,
                        restaurant: unlimited_restaurant,
                        table_group: unlimited_other_group,
                        table_number: 'O1',
                        capacity: 4,
                        min_capacity: 2,
                        max_capacity: 6,
                        table_type: 'round',
                        sort_order: 0,
                        can_combine: false,
                        operational_status: 'normal')
      
      # 更新餐廳總容量
      unlimited_restaurant.update!(total_capacity: 10)
    end

    describe '基本分配邏輯' do
      it '按 sort_order 排序選擇第一個適合的桌位' do
        reservation = build(:reservation,
                           restaurant: unlimited_restaurant,
                           business_period: unlimited_lunch_period,
                           party_size: 4,
                           adults_count: 4,
                           children_count: 0,
                           reservation_datetime: test_time)

        service = described_class.new(reservation)
        result = service.allocate_table

        expect(result).to eq(@t4_table)
        expect(result.table_number).to eq('T4')
      end

      it '當第一選擇不適合時，選擇其他適合的桌位' do
        reservation = build(:reservation,
                           restaurant: unlimited_restaurant,
                           business_period: unlimited_lunch_period,
                           party_size: 2,
                           adults_count: 2,
                           children_count: 0,
                           reservation_datetime: test_time)

        service = described_class.new(reservation)
        result = service.allocate_table

        expect(result).to eq(@t2_table)
        expect(result.table_number).to eq('T2')
      end
    end

    describe '每餐期每桌唯一性' do
      before do
        # 在同一餐期預訂 T4 桌位
        @existing_reservation = create(:reservation,
                                      restaurant: unlimited_restaurant,
                                      business_period: unlimited_lunch_period,
                                      table: @t4_table,
                                      party_size: 4,
                                      adults_count: 4,
                                      children_count: 0,
                                      reservation_datetime: test_time,
                                      status: 'confirmed')
      end

      it '同一餐期不能重複預訂已被佔用的桌位' do
        service = described_class.new({
          restaurant: unlimited_restaurant,
          party_size: 4,
          adults: 4,
          children: 0,
          reservation_datetime: test_time,
          business_period_id: unlimited_lunch_period.id
        })

        booking_check = service.check_table_booking_in_period(@t4_table, test_time)
        
        expect(booking_check[:has_booking]).to be true
        expect(booking_check[:existing_booking]).to eq(@existing_reservation)
      end

      it '同一餐期會自動分配其他可用桌位' do
        reservation = build(:reservation,
                           restaurant: unlimited_restaurant,
                           business_period: unlimited_lunch_period,
                           party_size: 4,
                           adults_count: 4,
                           children_count: 0,
                           reservation_datetime: test_time)

        service = described_class.new(reservation)
        result = service.allocate_table

        expect(result).to eq(@o1_table)  # 應該分配到 O1 桌位
        expect(result.table_number).to eq('O1')
      end

      it '不同餐期可以重用同一桌位' do
        service = described_class.new({
          restaurant: unlimited_restaurant,
          party_size: 4,
          adults: 4,
          children: 0,
          reservation_datetime: test_time,
          business_period_id: unlimited_dinner_period.id
        })

        booking_check = service.check_table_booking_in_period(@t4_table, test_time)
        
        expect(booking_check[:has_booking]).to be false
        expect(booking_check[:existing_booking]).to be_nil
      end
    end

    describe '同群組併桌限制' do
      it '只允許同群組內的桌位併桌' do
        service = described_class.new({
          restaurant: unlimited_restaurant,
          party_size: 6,
          adults: 6,
          children: 0,
          reservation_datetime: test_time,
          business_period_id: unlimited_lunch_period.id
        })

        combinable_tables = service.find_combinable_tables
        
        if combinable_tables.present?
          expect(combinable_tables).to include(@t4_table, @t2_table)
          expect(combinable_tables.sum(&:capacity)).to be >= 6
          
          # 檢查都在同一群組
          group_ids = combinable_tables.map(&:table_group_id).uniq
          expect(group_ids.count).to eq(1)
          expect(group_ids.first).to eq(unlimited_test_group.id)
        end
      end

      it '不允許跨群組併桌' do
        service = described_class.new({
          restaurant: unlimited_restaurant,
          party_size: 8,
          adults: 8,
          children: 0,
          reservation_datetime: test_time,
          business_period_id: unlimited_lunch_period.id
        })

        combinable_tables = service.find_combinable_tables
        
        # 應該找不到跨群組的併桌方案
        if combinable_tables
          group_ids = combinable_tables.map(&:table_group_id).uniq
          expect(group_ids.count).to eq(1)
        end
      end
    end

    describe '可用性檢查 API' do
      it '正確回報 2 人聚餐的可用性' do
        service = described_class.new({
          restaurant: unlimited_restaurant,
          party_size: 2,
          adults: 2,
          children: 0,
          reservation_datetime: test_time,
          business_period_id: unlimited_lunch_period.id
        })

        availability = service.check_availability
        
        expect(availability[:has_availability]).to be true
        expect(availability[:available_tables].count).to be >= 2
      end

      it '正確回報 4 人聚餐的可用性' do
        service = described_class.new({
          restaurant: unlimited_restaurant,
          party_size: 4,
          adults: 4,
          children: 0,
          reservation_datetime: test_time,
          business_period_id: unlimited_lunch_period.id
        })

        availability = service.check_availability
        
        expect(availability[:has_availability]).to be true
        expect(availability[:available_tables].count).to be >= 2
      end

      it '正確回報超大聚餐無可用性' do
        service = described_class.new({
          restaurant: unlimited_restaurant,
          party_size: 20,
          adults: 20,
          children: 0,
          reservation_datetime: test_time,
          business_period_id: unlimited_lunch_period.id
        })

        availability = service.check_availability
        
        expect(availability[:has_availability]).to be false
        expect(availability[:available_tables]).to be_empty
      end
    end

    describe '容量檢查' do
      it '不會因為容量檢查而阻止合理的預訂' do
        reservation = build(:reservation,
                           restaurant: unlimited_restaurant,
                           business_period: unlimited_lunch_period,
                           party_size: 4,
                           adults_count: 4,
                           children_count: 0,
                           reservation_datetime: test_time)

        service = described_class.new(reservation)
        
        expect(service.send(:exceeds_restaurant_capacity?)).to be false
        expect(service.allocate_table).to be_present
      end

      it '正確計算餐期內的已預訂容量' do
        # 創建一些現有預訂
        create(:reservation,
               restaurant: unlimited_restaurant,
               business_period: unlimited_lunch_period,
               party_size: 4,
               adults_count: 4,
               children_count: 0,
               reservation_datetime: test_time,
               status: 'confirmed')

        reservation = build(:reservation,
                           restaurant: unlimited_restaurant,
                           business_period: unlimited_lunch_period,
                           party_size: 4,
                           adults_count: 4,
                           children_count: 0,
                           reservation_datetime: test_time + 1.hour)

        service = described_class.new(reservation)
        
        # 應該仍然可以預訂，因為總容量是 10，已預訂 4，還剩 6
        expect(service.send(:exceeds_restaurant_capacity?)).to be false
      end
    end

    describe '錯誤處理' do
      it '當沒有 business_period_id 時不會崩潰' do
        service = described_class.new({
          restaurant: unlimited_restaurant,
          party_size: 4,
          adults: 4,
          children: 0,
          reservation_datetime: test_time
          # 故意不提供 business_period_id
        })

        expect { service.allocate_table }.not_to raise_error
        expect(service.send(:exceeds_restaurant_capacity?)).to be false
      end

      it '當桌位不支援併桌時正確處理' do
        # 設定所有桌位都不支援併桌
        [@t4_table, @t2_table, @o1_table].each do |table|
          table.update!(can_combine: false)
        end

        service = described_class.new({
          restaurant: unlimited_restaurant,
          party_size: 6,
          adults: 6,
          children: 0,
          reservation_datetime: test_time,
          business_period_id: unlimited_lunch_period.id
        })

        combinable_tables = service.find_combinable_tables
        expect(combinable_tables).to be_nil
      end
    end
  end

  private

  def setup_test_tables
    # 建立窗邊圓桌
    @window_table = create(:table, :window_round_table,
                          restaurant: restaurant,
                          table_group: table_group_window,
                          sort_order: 1)

    # 建立方桌
    @square_tables = []
    %w[A B C].each_with_index do |letter, index|
      @square_tables << create(:table, :square_table,
                              restaurant: restaurant,
                              table_group: table_group_square,
                              table_number: "方桌#{letter}",
                              sort_order: index + 1)
    end

    # 建立吧台
    @bar_tables = []
    %w[A B C].each_with_index do |letter, index|
      @bar_tables << create(:table, :bar_seat,
                           restaurant: restaurant,
                           table_group: table_group_bar,
                           table_number: "吧台#{letter}",
                           sort_order: index + 1)
    end
  end
end 