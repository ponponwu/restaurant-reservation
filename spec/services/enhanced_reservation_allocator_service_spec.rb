require 'rails_helper'

RSpec.describe EnhancedReservationAllocatorService, type: :service do
  let!(:restaurant) { create(:restaurant) }
  let!(:table_group) { create(:table_group, restaurant: restaurant, name: '主區', sort_order: 1) }

  let!(:reservation_period) do
    create(:reservation_period,
           restaurant: restaurant,
           start_time: '11:30',
           end_time: '14:30',
           weekday: 1) # 星期一
  end

  let!(:table1) { create(:table, restaurant: restaurant, table_group: table_group, table_number: 'A1', capacity: 4, max_capacity: 4, can_combine: true) }
  let!(:table2) { create(:table, restaurant: restaurant, table_group: table_group, table_number: 'A2', capacity: 4, max_capacity: 4, can_combine: true) }
  let!(:table3) { create(:table, restaurant: restaurant, table_group: table_group, table_number: 'A3', capacity: 2, max_capacity: 2, can_combine: true) }

  before do
    # 更新餐廳總容量和政策
    restaurant.update_cached_capacity

    policy = restaurant.reservation_policy || restaurant.create_reservation_policy
    policy.update!(
      max_party_size: 20,
      min_party_size: 1,
      advance_booking_days: 30,
      minimum_advance_hours: 1,
      unlimited_dining_time: false,
      default_dining_duration_minutes: 120
    )
  end

  describe '#allocate_table_with_optimistic_locking' do
    let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }

    context '基本桌位分配功能' do
      it '成功分配適合的單桌' do
        service = described_class.new({
                                        restaurant: restaurant,
                                        party_size: 4,
                                        adults: 4,
                                        children: 0,
                                        reservation_datetime: reservation_time,
                                        reservation_period_id: reservation_period.id
                                      })

        result = service.allocate_table_with_optimistic_locking

        expect(result).to be_present
        expect(result.capacity).to be >= 4
        expect([table1.id, table2.id]).to include(result.id)
      end

      it '為小人數分配適當大小的桌位' do
        service = described_class.new({
                                        restaurant: restaurant,
                                        party_size: 2,
                                        adults: 2,
                                        children: 0,
                                        reservation_datetime: reservation_time,
                                        reservation_period_id: reservation_period.id
                                      })

        result = service.allocate_table_with_optimistic_locking

        expect(result).to be_present
        expect(result.capacity).to be >= 2 # 應該分配能容納人數的桌位
        expect([table1.id, table2.id, table3.id]).to include(result.id)
      end

      it '當超過餐廳容量時返回 nil' do
        service = described_class.new({
                                        restaurant: restaurant,
                                        party_size: 100, # 超過總容量
                                        adults: 100,
                                        children: 0,
                                        reservation_datetime: reservation_time,
                                        reservation_period_id: reservation_period.id
                                      })

        result = service.allocate_table_with_optimistic_locking

        expect(result).to be_nil
      end
    end

    context '桌位佔用情況處理' do
      before do
        # 預先創建一個占用 table1 的預訂
        create(:reservation,
               restaurant: restaurant,
               table: table1,
               reservation_period: reservation_period,
               party_size: 2,
               adults_count: 2,
               children_count: 0,
               status: 'confirmed',
               reservation_datetime: reservation_time)
      end

      it '跳過已佔用的桌位' do
        service = described_class.new({
                                        restaurant: restaurant,
                                        party_size: 4,
                                        adults: 4,
                                        children: 0,
                                        reservation_datetime: reservation_time,
                                        reservation_period_id: reservation_period.id
                                      })

        result = service.allocate_table_with_optimistic_locking

        expect(result).to be_present
        expect(result.id).to eq(table2.id) # 應該選擇 table2 而不是已占用的 table1
      end

      it '當所有適合的桌位都被佔用時返回 nil' do
        # 也佔用 table2
        create(:reservation,
               restaurant: restaurant,
               table: table2,
               reservation_period: reservation_period,
               party_size: 2,
               adults_count: 2,
               children_count: 0,
               status: 'confirmed',
               reservation_datetime: reservation_time)

        service = described_class.new({
                                        restaurant: restaurant,
                                        party_size: 4,
                                        adults: 4,
                                        children: 0,
                                        reservation_datetime: reservation_time,
                                        reservation_period_id: reservation_period.id
                                      })

        result = service.allocate_table_with_optimistic_locking

        # table1 和 table2 都被佔用，table3 容量不足(2<4)，應該返回 nil
        expect(result).to be_nil
      end
    end
  end

  describe '#table_occupied_at_time?' do
    let(:service) do
      described_class.new({
                            restaurant: restaurant,
                            party_size: 2,
                            adults: 2,
                            children: 0,
                            reservation_datetime: reservation_time,
                            reservation_period_id: reservation_period.id
                          })
    end

    let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }

    context '時間重疊檢測' do
      it '檢測完全重疊的時間' do
        create(:reservation,
               restaurant: restaurant,
               table: table1,
               reservation_period: reservation_period,
               party_size: 2,
               adults_count: 2,
               children_count: 0,
               status: 'confirmed',
               reservation_datetime: reservation_time) # 完全相同時間

        result = service.send(:table_occupied_at_time?, table1, reservation_time)

        expect(result).to be true
      end

      it '檢測部分重疊的時間' do
        existing_time = reservation_time - 1.hour # 現有預訂在1小時前
        create(:reservation,
               restaurant: restaurant,
               table: table1,
               reservation_period: reservation_period,
               party_size: 2,
               adults_count: 2,
               children_count: 0,
               status: 'confirmed',
               reservation_datetime: existing_time)

        # 新預訂時間與現有預訂會重疊（假設用餐時間為2小時）
        result = service.send(:table_occupied_at_time?, table1, reservation_time)

        expect(result).to be true
      end

      it '不檢測出無重疊的時間' do
        existing_time = reservation_time - 3.hours # 現有預訂在3小時前
        create(:reservation,
               restaurant: restaurant,
               table: table1,
               reservation_period: reservation_period,
               party_size: 2,
               adults_count: 2,
               children_count: 0,
               status: 'confirmed',
               reservation_datetime: existing_time)

        # 3小時前的預訂不應該與當前時間重疊
        result = service.send(:table_occupied_at_time?, table1, reservation_time)

        expect(result).to be false
      end
    end

    context '併桌情況檢測' do
      let!(:table_combination) do
        reservation = create(:reservation,
                             restaurant: restaurant,
                             reservation_period: reservation_period,
                             party_size: 6,
                             adults_count: 6,
                             children_count: 0,
                             status: 'confirmed',
                             reservation_datetime: reservation_time)

        combination = TableCombination.new(
          reservation: reservation,
          name: '併桌A1+A2',
          notes: '系統自動分配併桌'
        )
        combination.restaurant_tables = [table1, table2]
        combination.save!
        combination
      end

      it '檢測到被併桌使用的桌位' do
        result1 = service.send(:table_occupied_at_time?, table1, reservation_time)
        result2 = service.send(:table_occupied_at_time?, table2, reservation_time)

        expect(result1).to be true
        expect(result2).to be true
      end

      it '不影響未被併桌使用的桌位' do
        result = service.send(:table_occupied_at_time?, table3, reservation_time)

        expect(result).to be false
      end
    end
  end

  describe '#exceeds_restaurant_capacity?' do
    let(:service) do
      described_class.new({
                            restaurant: restaurant,
                            party_size: party_size,
                            adults: party_size,
                            children: 0,
                            reservation_datetime: reservation_time,
                            reservation_period_id: reservation_period.id
                          })
    end

    let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }
    let(:party_size) { 4 }

    context '容量限制檢查' do
      it '當請求人數不超過剩餘容量時返回 false' do
        # 總容量是 10 (4+4+2)，請求 4 人，應該沒問題
        result = service.send(:exceeds_restaurant_capacity?)

        expect(result).to be false
      end

      it '當餐廳已滿時返回 true' do
        # 創建預訂佔滿大部分容量
        create(:reservation,
               restaurant: restaurant,
               table: table1,
               reservation_period: reservation_period,
               party_size: 4,
               adults_count: 4,
               children_count: 0,
               status: 'confirmed',
               reservation_datetime: reservation_time)

        create(:reservation,
               restaurant: restaurant,
               table: table2,
               reservation_period: reservation_period,
               party_size: 4,
               adults_count: 4,
               children_count: 0,
               status: 'confirmed',
               reservation_datetime: reservation_time)

        # 再創建一個佔用 table3 的預訂，確保餐廳完全客滿
        create(:reservation,
               restaurant: restaurant,
               table: table3,
               reservation_period: reservation_period,
               party_size: 2,
               adults_count: 2,
               children_count: 0,
               status: 'confirmed',
               reservation_datetime: reservation_time)

        # 現在餐廳已滿（4+4+2=10人，總容量10人），請求 4 人應該超過容量
        result = service.send(:exceeds_restaurant_capacity?)

        expect(result).to be true
      end

      it '正確計算時間重疊的容量' do
        # 驗證時間重疊的容量計算邏輯
        # 首先驗證空餐廳時不超過容量
        result = service.send(:exceeds_restaurant_capacity?)
        expect(result).to be false

        # 創建一個同時間的預訂，佔用6人容量
        create(:reservation,
               restaurant: restaurant,
               table: table1,
               reservation_period: reservation_period,
               party_size: 6,
               adults_count: 6,
               children_count: 0,
               status: 'confirmed',
               reservation_datetime: reservation_time)

        # 再嘗試預訂4人，總共10人剛好達到容量極限，應該沒問題
        result = service.send(:exceeds_restaurant_capacity?)
        expect(result).to be false

        # 但如果已有6人，再請求5人就會超過容量
        large_service = described_class.new({
                                              restaurant: restaurant,
                                              party_size: 5,
                                              adults: 5,
                                              children: 0,
                                              reservation_datetime: reservation_time,
                                              reservation_period_id: reservation_period.id
                                            })

        result = large_service.send(:exceeds_restaurant_capacity?)
        expect(result).to be true
      end
    end
  end

  describe '#check_availability_without_locking' do
    let(:service) do
      described_class.new({
                            restaurant: restaurant,
                            party_size: 4,
                            adults: 4,
                            children: 0,
                            reservation_datetime: reservation_time,
                            reservation_period_id: reservation_period.id
                          })
    end

    let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }

    it '當有可用桌位時返回可用性資訊' do
      result = service.check_availability_without_locking

      expect(result[:has_availability]).to be true
      expect(result[:allocation_type]).to eq(:single)
    end

    it '當沒有可用桌位時返回不可用' do
      # 佔滿所有桌位
      create(:reservation,
             restaurant: restaurant,
             table: table1,
             reservation_period: reservation_period,
             party_size: 2,
             adults_count: 2,
             children_count: 0,
             status: 'confirmed',
             reservation_datetime: reservation_time)

      create(:reservation,
             restaurant: restaurant,
             table: table2,
             reservation_period: reservation_period,
             party_size: 2,
             adults_count: 2,
             children_count: 0,
             status: 'confirmed',
             reservation_datetime: reservation_time)

      create(:reservation,
             restaurant: restaurant,
             table: table3,
             reservation_period: reservation_period,
             party_size: 2,
             adults_count: 2,
             children_count: 0,
             status: 'confirmed',
             reservation_datetime: reservation_time)

      result = service.check_availability_without_locking

      expect(result[:has_availability]).to be false
      expect(result[:allocation_type]).to eq(:none)
    end
  end

  describe '併發安全性測試' do
    let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }

    context '多線程同時分配相同桌位' do
      it '防止桌位重複分配（通過完整預訂流程）' do
        threads = []
        successful_reservations = []
        conflicts = []

        # 創建10個併發請求嘗試預訂相同時間
        10.times do |i|
          threads << Thread.new do
            reservation = restaurant.reservations.build(
              customer_name: "測試客戶#{i}",
              customer_phone: "091234567#{i % 10}",
              customer_email: "test#{i}@example.com",
              party_size: 2,
              adults_count: 2,
              children_count: 0,
              reservation_datetime: reservation_time,
              reservation_period_id: reservation_period.id,
              status: 'confirmed'
            )

            ActiveRecord::Base.transaction do
              service = described_class.new({
                                              restaurant: restaurant,
                                              party_size: 2,
                                              adults: 2,
                                              children: 0,
                                              reservation_datetime: reservation_time,
                                              reservation_period_id: reservation_period.id,
                                              reservation: reservation
                                            })

              allocated_table = service.allocate_table_with_optimistic_locking
              if allocated_table
                reservation.table = allocated_table
                reservation.save!
                successful_reservations << reservation
              end
            end
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
            conflicts << "Thread #{i}: #{e.message}"
          rescue StandardError => e
            conflicts << "Thread #{i}: #{e.message}"
          end
        end

        threads.each(&:join)

        # 驗證沒有重複分配相同桌位
        allocated_table_ids = successful_reservations.map(&:table_id).compact
        expect(allocated_table_ids).to eq(allocated_table_ids.uniq)

        # 應該有一些成功的預訂
        expect(successful_reservations.size).to be > 0
        expect(successful_reservations.size).to be <= 3 # 最多3張桌

        # 輸出調試信息
        puts "成功預訂: #{successful_reservations.size}, 衝突/失敗: #{conflicts.size}"
        puts "分配的桌位 IDs: #{allocated_table_ids}"

        # 樂觀鎖的主要作用是防止重複分配，而不是強制所有請求都進入衝突狀態
        # 如果容量檢查正確工作，大部分請求會在分配階段就被阻止
      end

      it '在高併發情況下維持容量限制（通過完整預訂流程）' do
        threads = []
        successful_reservations = []
        failed_attempts = []

        # 創建15個併發請求，每個請求2人（總共30人，超過餐廳容量10人）
        15.times do |i|
          threads << Thread.new do
            reservation = restaurant.reservations.build(
              customer_name: "測試客戶#{i}",
              customer_phone: "091234568#{i % 10}",
              customer_email: "test#{i}@example.com",
              party_size: 2,
              adults_count: 2,
              children_count: 0,
              reservation_datetime: reservation_time,
              reservation_period_id: reservation_period.id,
              status: 'confirmed'
            )

            ActiveRecord::Base.transaction do
              service = described_class.new({
                                              restaurant: restaurant,
                                              party_size: 2,
                                              adults: 2,
                                              children: 0,
                                              reservation_datetime: reservation_time,
                                              reservation_period_id: reservation_period.id,
                                              reservation: reservation
                                            })

              allocated_table = service.allocate_table_with_optimistic_locking
              if allocated_table
                reservation.table = allocated_table
                reservation.save!
                successful_reservations << reservation
              else
                failed_attempts << i
              end
            end
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
            failed_attempts << "Thread #{i}: #{e.message}"
          rescue StandardError => e
            failed_attempts << "Thread #{i}: #{e.message}"
          end
        end

        threads.each(&:join)

        # 驗證成功預訂的總人數不超過餐廳容量
        total_reserved_capacity = successful_reservations.sum(&:party_size)
        expect(total_reserved_capacity).to be <= restaurant.total_capacity

        # 應該有一些失敗的預訂（因為容量不足）
        expect(failed_attempts).not_to be_empty

        # 成功預訂的桌位不應該重複
        allocated_table_ids = successful_reservations.map(&:table_id).compact
        expect(allocated_table_ids).to eq(allocated_table_ids.uniq)
      end
    end

    context '併桌競爭條件測試' do
      before do
        # 讓餐廳支持併桌
        allow(restaurant).to receive(:can_combine_tables?).and_return(true)
        allow(restaurant).to receive(:max_tables_per_combination).and_return(2)
      end

      it '防止併桌中的桌位重複使用' do
        threads = []
        results = []

        # 一個線程嘗試併桌，另一個線程嘗試單桌使用相同桌位
        threads << Thread.new do
          service = described_class.new({
                                          restaurant: restaurant,
                                          party_size: 6, # 需要併桌
                                          adults: 6,
                                          children: 0,
                                          reservation_datetime: reservation_time,
                                          reservation_period_id: reservation_period.id
                                        })

          result = service.allocate_table_with_optimistic_locking
          results << { type: :combination, result: result }
        end

        threads << Thread.new do
          sleep(0.01) # 稍微延遲以增加競爭條件機會
          service = described_class.new({
                                          restaurant: restaurant,
                                          party_size: 2, # 單桌
                                          adults: 2,
                                          children: 0,
                                          reservation_datetime: reservation_time,
                                          reservation_period_id: reservation_period.id
                                        })

          result = service.allocate_table_with_optimistic_locking
          results << { type: :single, result: result }
        end

        threads.each(&:join)

        # 分析結果
        combination_result = results.find { |r| r[:type] == :combination }[:result]
        single_result = results.find { |r| r[:type] == :single }[:result]

        # 如果兩個都成功，確保沒有使用相同桌位
        if combination_result && single_result && combination_result.is_a?(Array)
          combination_table_ids = combination_result.map(&:id)
          expect(combination_table_ids).not_to include(single_result.id)
        end

        # 至少有一個應該成功
        expect([combination_result, single_result].compact).not_to be_empty
      end
    end

    context '時間重疊競爭條件測試' do
      it '正確處理邊界時間的競爭條件' do
        # 創建一個已存在的預訂
        existing_reservation = create(:reservation,
                                      restaurant: restaurant,
                                      table: table1,
                                      reservation_period: reservation_period,
                                      party_size: 2,
                                      adults_count: 2,
                                      children_count: 0,
                                      status: 'confirmed',
                                      reservation_datetime: reservation_time)

        threads = []
        results = []

        # 多個線程嘗試在重疊時間分配相同桌位
        5.times do |i|
          threads << Thread.new do
            # 稍微不同的時間，但會造成重疊
            test_time = reservation_time + (i * 15).minutes

            service = described_class.new({
                                            restaurant: restaurant,
                                            party_size: 2,
                                            adults: 2,
                                            children: 0,
                                            reservation_datetime: test_time,
                                            reservation_period_id: reservation_period.id
                                          })

            # 檢查是否能檢測到時間重疊
            occupied = service.send(:table_occupied_at_time?, table1, test_time)
            results << { time: test_time, occupied: occupied, thread: i }
          end
        end

        threads.each(&:join)

        # 所有重疊時間的檢查都應該返回 true（桌位被佔用）
        overlapping_results = results.select do |r|
          # 檢查是否與現有預訂時間重疊（假設用餐時間2小時）
          duration = 120.minutes
          existing_end = existing_reservation.reservation_datetime + duration
          new_end = r[:time] + duration

          r[:time] < existing_end && new_end > existing_reservation.reservation_datetime
        end

        overlapping_results.each do |result|
          expect(result[:occupied]).to be(true),
                                       "Thread #{result[:thread]} at #{result[:time]} should detect overlap"
        end
      end
    end
  end

  describe '錯誤處理和邊界測試' do
    let(:reservation_time) { 1.day.from_now.change(hour: 12, min: 0) }

    context '異常情況處理' do
      it '處理無效的日期時間參數' do
        service = described_class.new({
                                        restaurant: restaurant,
                                        party_size: 2,
                                        adults: 2,
                                        children: 0,
                                        reservation_datetime: 'invalid_date',
                                        reservation_period_id: reservation_period.id
                                      })

        expect do
          service.allocate_table_with_optimistic_locking
        end.not_to raise_error

        result = service.allocate_table_with_optimistic_locking
        expect(result).to be_nil
      end

      it '處理空的人數參數' do
        service = described_class.new({
                                        restaurant: restaurant,
                                        party_size: 0,
                                        adults: 0,
                                        children: 0,
                                        reservation_datetime: reservation_time,
                                        reservation_period_id: reservation_period.id
                                      })

        result = service.allocate_table_with_optimistic_locking
        expect(result).to be_nil
      end

      it '處理資料庫連接錯誤' do
        service = described_class.new({
                                        restaurant: restaurant,
                                        party_size: 2,
                                        adults: 2,
                                        children: 0,
                                        reservation_datetime: reservation_time,
                                        reservation_period_id: reservation_period.id
                                      })

        # 模擬資料庫錯誤
        allow(restaurant.restaurant_tables).to receive(:active).and_raise(StandardError, 'Database error')

        result = service.allocate_table_with_optimistic_locking
        expect(result).to be_nil
      end
    end

    context '邊界值測試' do
      it '處理最大人數限制' do
        service = described_class.new({
                                        restaurant: restaurant,
                                        party_size: restaurant.total_capacity,
                                        adults: restaurant.total_capacity,
                                        children: 0,
                                        reservation_datetime: reservation_time,
                                        reservation_period_id: reservation_period.id
                                      })

        # 在餐廳總容量範圍內應該可以分配
        result = service.send(:exceeds_restaurant_capacity?)
        expect(result).to be false
      end

      it '處理最小人數限制' do
        service = described_class.new({
                                        restaurant: restaurant,
                                        party_size: 1,
                                        adults: 1,
                                        children: 0,
                                        reservation_datetime: reservation_time,
                                        reservation_period_id: reservation_period.id
                                      })

        result = service.allocate_table_with_optimistic_locking
        expect(result).to be_present
      end
    end
  end
end
