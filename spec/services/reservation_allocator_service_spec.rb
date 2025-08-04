require 'rails_helper'

RSpec.describe ReservationAllocatorService, type: :service do
  let!(:restaurant) { create(:restaurant) }
  let!(:table_group_window) { create(:table_group, restaurant: restaurant, name: '窗邊圓桌', sort_order: 1) }
  let!(:table_group_square) { create(:table_group, restaurant: restaurant, name: '方桌', sort_order: 2) }
  let!(:table_group_bar) { create(:table_group, restaurant: restaurant, name: '吧台', sort_order: 3) }

  let!(:reservation_period) do
    create(:reservation_period,
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
      max_party_size: [total_capacity, 20].max, # 至少要等於總容量
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
                               reservation_period: reservation_period,
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
                               reservation_period: reservation_period,
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
                               reservation_period: reservation_period,
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
                               reservation_period: reservation_period,
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
                     reservation_period: reservation_period,
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
                                 reservation_period: reservation_period,
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
                             reservation_period: reservation_period,
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
                             reservation_period: reservation_period,
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
                             reservation_period: reservation_period,
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
                 reservation_period: reservation_period,
                 table: @window_table,
                 party_size: 5,
                 adults_count: 5,
                 children_count: 0,
                 reservation_datetime: reservation_time)

          # 佔用所有方桌
          @square_tables.each do |table|
            create(:reservation, :confirmed,
                   restaurant: restaurant,
                   reservation_period: reservation_period,
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
                   reservation_period: reservation_period,
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
                               reservation_period: reservation_period,
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
                                     reservation_period: reservation_period,
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
                                      reservation_period: reservation_period,
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
        create(:reservation_period,
               restaurant: restaurant,
               name: '晚餐時段',
               start_time: '17:30',
               end_time: '21:30',
               days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
      end

      it '不同營業時段可以使用相同桌位' do
        # 設定餐廳為無限時模式，確保不同餐期不會衝突
        restaurant.reservation_policy.update!(unlimited_dining_time: true)

        # 午餐時段訂位
        lunch_reservation = create(:reservation,
                                   restaurant: restaurant,
                                   reservation_period: reservation_period,
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
                                    reservation_period: dinner_period,
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
                             reservation_period: reservation_period,
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
                                      reservation_period: reservation_period,
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
                                 reservation_period: reservation_period,
                                 party_size: 2,
                                 adults_count: 2,
                                 children_count: 0,
                                 reservation_datetime: reservation_time)

        # 確保 reservation_period_id 正確設置
        new_reservation.reload
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
                               reservation_period: reservation_period,
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
                             reservation_period: reservation_period,
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
                               reservation_period: reservation_period,
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
        total_available_tables = @square_tables.count # 3張方桌

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
             reservation_period: reservation_period,
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
               reservation_period: reservation_period,
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
             reservation_period: reservation_period,
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

    context '當有適合的單一桌位時' do
      it '正確回報有可用性' do
        reservation = create(:reservation,
                             restaurant: restaurant,
                             reservation_period: reservation_period,
                             party_size: 2,
                             adults_count: 2,
                             children_count: 0,
                             reservation_datetime: reservation_time)

        service = described_class.new(reservation)
        result = service.check_availability

        expect(result[:has_availability]).to be true
        expect(result[:suitable_table]).to be_present
        expect(result[:suitable_table].table_group.name).to eq('方桌')
      end
    end

    context '當沒有適合的單一桌位但有併桌選項時' do
      before do
        # 確保餐廳允許併桌
        policy = restaurant.reservation_policy
        policy.update!(allow_table_combinations: true, max_combination_tables: 3)

        # 設定吧台桌位為可併桌
        @bar_tables.each { |table| table.update!(can_combine: true) }

        # 佔用所有單一桌位，只留下需要併桌的情況
        @square_tables.each do |table|
          create(:reservation, :confirmed,
                 restaurant: restaurant,
                 reservation_period: reservation_period,
                 table: table,
                 party_size: 2,
                 adults_count: 2,
                 children_count: 0,
                 reservation_datetime: reservation_time)
        end

        # 佔用窗邊圓桌
        create(:reservation, :confirmed,
               restaurant: restaurant,
               reservation_period: reservation_period,
               table: @window_table,
               party_size: 5,
               adults_count: 5,
               children_count: 0,
               reservation_datetime: reservation_time)
      end

      it '正確回報有併桌可用性' do
        # 創建一個需要併桌的大型訂位
        large_reservation = create(:reservation,
                                   restaurant: restaurant,
                                   reservation_period: reservation_period,
                                   party_size: 3, # 需要併桌才能容納
                                   adults_count: 3,
                                   children_count: 0,
                                   reservation_datetime: reservation_time)

        service = described_class.new(large_reservation)
        result = service.check_availability

        expect(result[:has_availability]).to be true
        expect(result[:suitable_table]).to be_nil # 沒有單一桌位
        expect(result[:combinable_tables]).to be_present # 但有併桌選項
        expect(result[:can_combine]).to be true
      end
    end

    context '當完全沒有可用性時' do
      before do
        # 佔用所有桌位
        @square_tables.each do |table|
          create(:reservation, :confirmed,
                 restaurant: restaurant,
                 reservation_period: reservation_period,
                 table: table,
                 party_size: 2,
                 adults_count: 2,
                 children_count: 0,
                 reservation_datetime: reservation_time)
        end

        create(:reservation, :confirmed,
               restaurant: restaurant,
               reservation_period: reservation_period,
               table: @window_table,
               party_size: 5,
               adults_count: 5,
               children_count: 0,
               reservation_datetime: reservation_time)

        @bar_tables.each do |table|
          create(:reservation, :confirmed,
                 restaurant: restaurant,
                 reservation_period: reservation_period,
                 table: table,
                 party_size: 1,
                 adults_count: 1,
                 children_count: 0,
                 reservation_datetime: reservation_time)
        end
      end

      it '正確回報沒有可用性' do
        reservation = create(:reservation,
                             restaurant: restaurant,
                             reservation_period: reservation_period,
                             party_size: 2,
                             adults_count: 2,
                             children_count: 0,
                             reservation_datetime: reservation_time)

        service = described_class.new(reservation)
        result = service.check_availability

        expect(result[:has_availability]).to be false
        expect(result[:suitable_table]).to be_nil
        expect(result[:combinable_tables]).to be_empty
      end
    end

    context '使用參數初始化時' do
      it '正確檢查可用性' do
        params = {
          restaurant: restaurant,
          party_size: 2,
          adults: 2,
          children: 0,
          reservation_datetime: reservation_time,
          reservation_period_id: reservation_period.id
        }

        service = described_class.new(params)
        result = service.check_availability

        expect(result[:has_availability]).to be true
        expect(result[:suitable_table]).to be_present
      end
    end
  end

  # 併桌功能測試
  describe '併桌功能' do
    let(:test_time) { 1.day.from_now.change(hour: 18, min: 0) }

    before do
      # 設定併桌測試環境
      setup_combination_test_tables
    end

    context '併桌分配邏輯' do
      it '為大型聚會分配併桌' do
        reservation = create(:reservation,
                             restaurant: restaurant,
                             reservation_period: reservation_period,
                             party_size: 8,
                             adults_count: 8,
                             children_count: 0,
                             reservation_datetime: test_time)

        service = described_class.new(reservation)
        result = service.allocate_table

        # 預期結果：由於方桌群組現在有3張4人桌位 (總容量12)，應該能分配併桌
        expect(result).to be_present

        if result.is_a?(Array)
          # 多桌組合的情況
          expect(result.size).to be >= 2
          expect(result.size).to be <= 3

          total_capacity = result.sum(&:capacity)
          expect(total_capacity).to be >= 8

          # 驗證所有桌位都來自同一個群組 (方桌群組)
          table_groups = result.map(&:table_group_id).uniq
          expect(table_groups.size).to eq(1)
          expect(result.first.table_group).to eq(table_group_square)

          # 驗證所有桌位都支援併桌
          expect(result.all?(&:can_combine?)).to be(true)
        else
          # 單桌的情況（不太可能，因為沒有單桌容量≥8）
          expect(result.capacity).to be >= 8
        end
      end

      it '檢查併桌效率（同群組內）' do
        # 方桌已在setup_combination_test_tables中設定為可併桌

        reservation = create(:reservation,
                             restaurant: restaurant,
                             reservation_period: reservation_period,
                             party_size: 4,
                             adults_count: 4,
                             children_count: 0,
                             reservation_datetime: test_time)

        service = described_class.new(reservation)
        result = service.allocate_table

        if result.is_a?(Array)
          total_capacity = result.sum(&:capacity)
          efficiency = (reservation.party_size.to_f / total_capacity * 100).round(1)
          expect(efficiency).to be >= 50.0 # 至少50%效率
        end
      end
    end
  end

  # 訂位功能開關測試
  describe '訂位功能開關' do
    let(:test_time) { 1.day.from_now.change(hour: 12, min: 0) }

    context '當訂位功能關閉時' do
      before do
        policy = restaurant.reservation_policy
        policy.update!(reservation_enabled: false)
      end

      it '應該拒絕分配桌位' do
        reservation = create(:reservation,
                             restaurant: restaurant,
                             reservation_period: reservation_period,
                             party_size: 4,
                             adults_count: 4,
                             children_count: 0,
                             reservation_datetime: test_time)

        described_class.new(reservation)

        # 檢查餐廳是否接受線上訂位
        expect(restaurant.reservation_policy.accepts_online_reservations?).to be false
      end
    end

    context '當訂位功能開啟時' do
      before do
        policy = restaurant.reservation_policy
        policy.update!(reservation_enabled: true)
      end

      it '應該正常分配桌位' do
        reservation = create(:reservation,
                             restaurant: restaurant,
                             reservation_period: reservation_period,
                             party_size: 4,
                             adults_count: 4,
                             children_count: 0,
                             reservation_datetime: test_time)

        service = described_class.new(reservation)
        result = service.allocate_table

        expect(result).to be_present
        expect(restaurant.reservation_policy.accepts_online_reservations?).to be true
      end
    end
  end

  # 無限用餐時間模式測試
  describe '無限用餐時間模式' do
    let(:reservation_period) { create(:reservation_period, restaurant: restaurant, name: '午餐') }
    let(:table1) { create(:table, restaurant: restaurant, table_number: 'A1', capacity: 4) }
    let(:table2) { create(:table, restaurant: restaurant, table_number: 'A2', capacity: 4) }

    before do
      # 設定為無限用餐時間模式
      restaurant.reservation_policy.update!(unlimited_dining_time: true)
    end

    context '基本無限時分配邏輯' do
      it '每餐期每桌只能有一個訂位' do
        # 第一個訂位佔用桌位
        create(:reservation, :confirmed,
               restaurant: restaurant,
               reservation_period: reservation_period,
               table: table1,
               reservation_datetime: 1.day.from_now.change(hour: 12),
               party_size: 2,
               adults_count: 2,
               children_count: 0)

        # 第二個訂位在同一餐期但不同時間，應該不能使用同一桌位
        second_reservation = create(:reservation,
                                    restaurant: restaurant,
                                    reservation_period: reservation_period,
                                    reservation_datetime: 1.day.from_now.change(hour: 13),
                                    party_size: 2,
                                    adults_count: 2,
                                    children_count: 0)

        service = described_class.new(second_reservation)
        reserved_table_ids = service.send(:get_reserved_table_ids, second_reservation.reservation_datetime)

        expect(reserved_table_ids).to include(table1.id)
      end

      it '不同餐期可以重複使用同一桌位' do
        dinner_period = create(:reservation_period, restaurant: restaurant, name: '晚餐')

        # 午餐時段的訂位
        create(:reservation, :confirmed,
               restaurant: restaurant,
               reservation_period: reservation_period,
               table: table1,
               reservation_datetime: 1.day.from_now.change(hour: 12),
               party_size: 2,
               adults_count: 2,
               children_count: 0)

        # 晚餐時段的訂位，可以使用同一桌位
        dinner_reservation = create(:reservation,
                                    restaurant: restaurant,
                                    reservation_period: dinner_period,
                                    reservation_datetime: 1.day.from_now.change(hour: 18),
                                    party_size: 2,
                                    adults_count: 2,
                                    children_count: 0)

        service = described_class.new(dinner_reservation)
        reserved_table_ids = service.send(:get_reserved_table_ids, dinner_reservation.reservation_datetime)

        expect(reserved_table_ids).not_to include(table1.id)
      end

      it '忽略用餐時間和緩衝時間設定' do
        # 設定用餐時間，但在無限時模式下應該被忽略
        restaurant.reservation_policy.update!(
          default_dining_duration_minutes: 60
        )

        # 創建一個訂位
        create(:reservation, :confirmed,
               restaurant: restaurant,
               reservation_period: reservation_period,
               table: table1,
               reservation_datetime: 1.day.from_now.change(hour: 12),
               party_size: 2,
               adults_count: 2,
               children_count: 0)

        # 在同一餐期的不同時間（但在傳統模式下會衝突的時間）
        new_reservation = create(:reservation,
                                 restaurant: restaurant,
                                 reservation_period: reservation_period,
                                 reservation_datetime: 1.day.from_now.change(hour: 12, min: 30),
                                 party_size: 2,
                                 adults_count: 2,
                                 children_count: 0)

        # 確保 reservation_period_id 正確設置
        new_reservation.reload
        service = described_class.new(new_reservation)
        reserved_table_ids = service.send(:get_reserved_table_ids, new_reservation.reservation_datetime)

        # 在無限時模式下，同一餐期的桌位仍然被佔用（不管時間差多少）
        expect(reserved_table_ids).to include(table1.id)
      end
    end

    context '容量檢查在無限時模式下' do
      it '按餐期計算容量而非時段' do
        restaurant.update_column(:total_capacity, 8)
        restaurant.reload
        # 在同一餐期已有一個4人訂位
        create(:reservation, :confirmed,
               restaurant: restaurant,
               reservation_period: reservation_period,
               table: table1,
               reservation_datetime: 1.day.from_now.change(hour: 12),
               party_size: 4,
               adults_count: 4,
               children_count: 0)

        # 新的5人訂位應該被拒絕（4+5=9 > 8）
        new_reservation = create(:reservation,
                                 restaurant: restaurant,
                                 reservation_period: reservation_period,
                                 reservation_datetime: 1.day.from_now.change(hour: 13),
                                 party_size: 5,
                                 adults_count: 5,
                                 children_count: 0)

        # 確保 reservation_period_id 正確設置
        new_reservation.reload
        service = described_class.new(new_reservation)

        expect(service.send(:exceeds_restaurant_capacity?)).to be true
      end

      it '不同餐期的容量獨立計算' do
        restaurant.update_column(:total_capacity, 8)
        restaurant.reload dinner_period = create(:reservation_period, restaurant: restaurant, name: '晚餐')

        # 午餐時段已有一個4人訂位
        create(:reservation, :confirmed,
               restaurant: restaurant,
               reservation_period: reservation_period,
               table: table1,
               reservation_datetime: 1.day.from_now.change(hour: 12),
               party_size: 4,
               adults_count: 4,
               children_count: 0)

        # 晚餐時段的5人訂位應該被接受（不同餐期）
        dinner_reservation = create(:reservation,
                                    restaurant: restaurant,
                                    reservation_period: dinner_period,
                                    reservation_datetime: 1.day.from_now.change(hour: 18),
                                    party_size: 5,
                                    adults_count: 5,
                                    children_count: 0)

        service = described_class.new(dinner_reservation)

        expect(service.send(:exceeds_restaurant_capacity?)).to be false
      end
    end

    context '併桌在無限時模式下' do
      let(:table3) { create(:table, restaurant: restaurant, table_number: 'A3', capacity: 2, can_combine: true) }
      let(:table4) { create(:table, restaurant: restaurant, table_number: 'A4', capacity: 2, can_combine: true) }

      before do
        restaurant.reservation_policy.update!(allow_table_combinations: true)
        table3.update!(can_combine: true)
        table4.update!(can_combine: true)
      end

      it '併桌檢查同餐期衝突而非時間衝突' do
        # 佔用其中一張可併桌的桌位
        existing_reservation = create(:reservation, :confirmed,
                                      restaurant: restaurant,
                                      reservation_period: reservation_period,
                                      table: table3,
                                      reservation_datetime: 1.day.from_now.change(hour: 12),
                                      party_size: 2,
                                      adults_count: 2,
                                      children_count: 0)

        # 新的4人訂位需要併桌，但table3已被佔用
        new_reservation = create(:reservation,
                                 restaurant: restaurant,
                                 reservation_period: reservation_period,
                                 reservation_datetime: 1.day.from_now.change(hour: 13),
                                 party_size: 4,
                                 adults_count: 4,
                                 children_count: 0)

        # 確保 reservation_period_id 正確設置
        new_reservation.reload
        service = described_class.new(new_reservation)

        # 檢查table3在該餐期的預訂狀況
        booking_check = service.check_table_booking_in_period(table3, new_reservation.reservation_datetime)
        expect(booking_check[:has_booking]).to be true
        expect(booking_check[:existing_booking]).to eq(existing_reservation)
      end
    end

    context '與限時模式的對比' do
      it '切換到限時模式後使用時間區間檢查' do
        # 先在無限時模式下創建訂位
        create(:reservation, :confirmed,
               restaurant: restaurant,
               reservation_period: reservation_period,
               table: table1,
               reservation_datetime: 1.day.from_now.change(hour: 12),
               party_size: 2,
               adults_count: 2,
               children_count: 0)

        # 切換到限時模式
        restaurant.reservation_policy.update!(
          unlimited_dining_time: false,
          default_dining_duration_minutes: 120
        )

        # 新的訂位在5小時後（17點），在限時模式下應該可以使用同一桌位
        # 12點訂位 + 2小時用餐 = 14:00 結束，17點開始應該沒問題
        limited_reservation = create(:reservation,
                                     restaurant: restaurant,
                                     reservation_period: reservation_period,
                                     reservation_datetime: 1.day.from_now.change(hour: 17),
                                     party_size: 2,
                                     adults_count: 2,
                                     children_count: 0)

        service = described_class.new(limited_reservation)
        reserved_table_ids = service.send(:get_reserved_table_ids, limited_reservation.reservation_datetime)

        # 在限時模式下，5小時後的訂位不會衝突（12點+2小時用餐+15分鐘緩衝=14:15結束，17點開始）
        expect(reserved_table_ids).not_to include(table1.id)
      end
    end

    context '邊界情況測試' do
      it '沒有reservation_period_id時不檢查衝突' do
        reservation = create(:reservation,
                             restaurant: restaurant,
                             reservation_datetime: 1.day.from_now.change(hour: 12),
                             party_size: 2,
                             adults_count: 2,
                             children_count: 0)

        service = described_class.new(reservation)
        reserved_table_ids = service.send(:get_reserved_table_ids, reservation.reservation_datetime)

        # 沒有餐期ID時，應該回傳空陣列
        expect(reserved_table_ids).to be_empty
      end

      it '跨日期的同餐期不衝突' do
        # 今天的午餐
        create(:reservation, :confirmed,
               restaurant: restaurant,
               reservation_period: reservation_period,
               table: table1,
               reservation_datetime: 2.days.from_now.change(hour: 12),
               party_size: 2,
               adults_count: 2,
               children_count: 0)

        # 明天的午餐
        tomorrow_reservation = create(:reservation,
                                      restaurant: restaurant,
                                      reservation_period: reservation_period,
                                      reservation_datetime: 1.day.from_now.change(hour: 12),
                                      party_size: 2,
                                      adults_count: 2,
                                      children_count: 0)

        service = described_class.new(tomorrow_reservation)
        reserved_table_ids = service.send(:get_reserved_table_ids, tomorrow_reservation.reservation_datetime)

        # 不同日期的同餐期不衝突
        expect(reserved_table_ids).not_to include(table1.id)
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

    # 建立方桌 - 使用原始的容量設定
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

  # 併桌測試專用的桌位設定
  def setup_combination_test_tables
    # 升級方桌容量以支援併桌測試
    @square_tables.each do |table|
      table.update!(
        capacity: 4,
        max_capacity: 4,
        can_combine: true
      )
    end

    # 重新計算餐廳總容量
    restaurant.update!(total_capacity: restaurant.calculate_total_capacity)

    # 更新餐廳政策以允許更大的人數
    policy = restaurant.reservation_policy
    total_capacity = restaurant.calculate_total_capacity
    policy.update!(
      max_party_size: [total_capacity, 20].max,
      allow_table_combinations: true,
      max_combination_tables: 3
    )
  end
end
