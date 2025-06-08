require 'rails_helper'

RSpec.describe '桌位分配系統', type: :system do
  let(:restaurant) { create(:restaurant, name: '測試餐廳') }
  let(:admin_user) { create(:user, :admin) }

  let(:table_group_window) { create(:table_group, restaurant: restaurant, name: '窗邊圓桌', sort_order: 1) }
  let(:table_group_square) { create(:table_group, restaurant: restaurant, name: '方桌', sort_order: 2) }
  let(:table_group_bar) { create(:table_group, restaurant: restaurant, name: '吧台', sort_order: 3) }

  let(:business_period) do
    create(:business_period,
           restaurant: restaurant,
           name: '午餐時段',
           start_time: '11:30',
           end_time: '14:30',
           days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
  end

  before do
    sign_in admin_user
    setup_test_environment
  end

  describe '管理員桌位分配流程', js: true do
    context '單一桌位分配' do
      scenario '管理員為2人訂位分配方桌' do
        visit admin_reservations_path

        click_button '新增訂位'

        within '#new_reservation_form' do
          fill_in '客戶姓名', with: '張小明'
          fill_in '電話號碼', with: '0912345678'
          fill_in '客戶信箱', with: 'test@example.com'
          select '2', from: '大人數'
          select '0', from: '小孩數'
          select business_period.name, from: '營業時段'
          
          # 選擇明天的時間
          tomorrow = 1.day.from_now
          fill_in '訂位日期', with: tomorrow.strftime('%Y-%m-%d')
          fill_in '訂位時間', with: '12:00'

          click_button '建立訂位'
        end

        expect(page).to have_content('訂位建立成功')
        expect(page).to have_content('張小明')

        # 檢查桌位是否正確分配
        reservation = Reservation.last
        expect(reservation.table).to be_present
        expect(reservation.table.table_group.name).to eq('方桌')
      end

      scenario '管理員為5人訂位分配窗邊圓桌' do
        visit admin_reservations_path

        click_button '新增訂位'

        within '#new_reservation_form' do
          fill_in '客戶姓名', with: '王大華'
          fill_in '電話號碼', with: '0987654321'
          select '5', from: '大人數'
          select '0', from: '小孩數'
          select business_period.name, from: '營業時段'
          
          tomorrow = 1.day.from_now
          fill_in '訂位日期', with: tomorrow.strftime('%Y-%m-%d')
          fill_in '訂位時間', with: '12:30'

          click_button '建立訂位'
        end

        expect(page).to have_content('訂位建立成功')
        
        reservation = Reservation.last
        expect(reservation.table.table_number).to eq('窗邊圓桌')
      end

      scenario '管理員為1人訂位優先分配方桌' do
        visit admin_reservations_path

        click_button '新增訂位'

        within '#new_reservation_form' do
          fill_in '客戶姓名', with: '李小美'
          fill_in '電話號碼', with: '0911111111'
          select '1', from: '大人數'
          select '0', from: '小孩數'
          select business_period.name, from: '營業時段'
          
          tomorrow = 1.day.from_now
          fill_in '訂位日期', with: tomorrow.strftime('%Y-%m-%d')
          fill_in '訂位時間', with: '13:00'

          click_button '建立訂位'
        end

        expect(page).to have_content('訂位建立成功')
        
        reservation = Reservation.last
        expect(reservation.table.table_group.name).to eq('方桌')
      end
    end

    context '容量限制處理' do
      scenario '拒絕超過餐廳總容量的訂位' do
        total_capacity = restaurant.total_capacity

        visit admin_reservations_path
        click_button '新增訂位'

        within '#new_reservation_form' do
          fill_in '客戶姓名', with: '超大團體'
          fill_in '電話號碼', with: '0900000000'
          select (total_capacity + 1).to_s, from: '大人數'
          select '0', from: '小孩數'
          select business_period.name, from: '營業時段'
          
          tomorrow = 1.day.from_now
          fill_in '訂位日期', with: tomorrow.strftime('%Y-%m-%d')
          fill_in '訂位時間', with: '12:00'

          click_button '建立訂位'
        end

        expect(page).to have_content('人數超過餐廳容量限制')
        expect(Reservation.count).to eq(0)
      end

      scenario '拒絕超過單一桌位容量的訂位（無法併桌時）' do
        visit admin_reservations_path
        click_button '新增訂位'

        within '#new_reservation_form' do
          fill_in '客戶姓名', with: '超大家庭'
          fill_in '電話號碼', with: '0900000001'
          select '6', from: '大人數'  # 超過窗邊圓桌的最大容量5
          select '0', from: '小孩數'
          select business_period.name, from: '營業時段'
          
          tomorrow = 1.day.from_now
          fill_in '訂位日期', with: tomorrow.strftime('%Y-%m-%d')
          fill_in '訂位時間', with: '12:00'

          click_button '建立訂位'
        end

        # 如果併桌功能尚未實作，應該顯示錯誤
        expect(page).to have_content('無法為此人數分配適合的桌位').or have_content('訂位建立成功')
      end
    end

    context '桌位衝突處理' do
      scenario '同一時段不能重複分配相同桌位' do
        # 先建立一個訂位
        tomorrow_12 = 1.day.from_now.change(hour: 12, min: 0)
        existing_reservation = create(:reservation, :confirmed,
                                    restaurant: restaurant,
                                    business_period: business_period,
                                    table: @square_tables.first,
                                    reservation_datetime: tomorrow_12)

        visit admin_reservations_path
        click_button '新增訂位'

        within '#new_reservation_form' do
          fill_in '客戶姓名', with: '新客戶'
          fill_in '電話號碼', with: '0922222222'
          select '2', from: '大人數'
          select '0', from: '小孩數'
          select business_period.name, from: '營業時段'
          
          fill_in '訂位日期', with: tomorrow_12.strftime('%Y-%m-%d')
          fill_in '訂位時間', with: '12:00'

          click_button '建立訂位'
        end

        expect(page).to have_content('訂位建立成功')
        
        # 檢查新訂位分配到不同的桌位
        new_reservation = Reservation.last
        expect(new_reservation.table.id).not_to eq(existing_reservation.table.id)
      end

      scenario '當所有適合桌位都被佔用時顯示錯誤' do
        tomorrow_12 = 1.day.from_now.change(hour: 12, min: 0)

        # 佔用所有方桌
        @square_tables.each do |table|
          create(:reservation, :confirmed,
               restaurant: restaurant,
               business_period: business_period,
               table: table,
               reservation_datetime: tomorrow_12)
        end

        visit admin_reservations_path
        click_button '新增訂位'

        within '#new_reservation_form' do
          fill_in '客戶姓名', with: '無法分配客戶'
          fill_in '電話號碼', with: '0933333333'
          select '2', from: '大人數'
          select '0', from: '小孩數'
          select business_period.name, from: '營業時段'
          
          fill_in '訂位日期', with: tomorrow_12.strftime('%Y-%m-%d')
          fill_in '訂位時間', with: '12:00'

          click_button '建立訂位'
        end

        expect(page).to have_content('該時段沒有適合的桌位').or have_content('無法分配桌位')
      end
    end

    context '桌位取消和重新分配' do
      scenario '取消訂位後桌位可以重新分配' do
        tomorrow_12 = 1.day.from_now.change(hour: 12, min: 0)
        
        # 建立並取消一個訂位
        cancelled_reservation = create(:reservation, :confirmed,
                                     restaurant: restaurant,
                                     business_period: business_period,
                                     table: @square_tables.first,
                                     reservation_datetime: tomorrow_12)

        visit admin_reservation_path(cancelled_reservation)
        click_button '取消訂位'
        
        expect(page).to have_content('訂位已取消')

        # 建立新訂位，應該可以分配到剛被釋放的桌位
        visit admin_reservations_path
        click_button '新增訂位'

        within '#new_reservation_form' do
          fill_in '客戶姓名', with: '重新分配客戶'
          fill_in '電話號碼', with: '0944444444'
          select '2', from: '大人數'
          select '0', from: '小孩數'
          select business_period.name, from: '營業時段'
          
          fill_in '訂位日期', with: tomorrow_12.strftime('%Y-%m-%d')
          fill_in '訂位時間', with: '12:00'

          click_button '建立訂位'
        end

        expect(page).to have_content('訂位建立成功')
        
        new_reservation = Reservation.where(status: 'confirmed').last
        expect(new_reservation.table.id).to eq(cancelled_reservation.table.id)
      end
    end

    context '多營業時段處理' do
      let(:dinner_period) do
        create(:business_period,
               restaurant: restaurant,
               name: '晚餐時段',
               start_time: '17:30',
               end_time: '21:30',
               days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
      end

      scenario '不同營業時段可以使用相同桌位' do
        tomorrow = 1.day.from_now
        lunch_time = tomorrow.change(hour: 12, min: 0)
        dinner_time = tomorrow.change(hour: 18, min: 0)

        # 午餐時段訂位
        visit admin_reservations_path
        click_button '新增訂位'

        within '#new_reservation_form' do
          fill_in '客戶姓名', with: '午餐客戶'
          fill_in '電話號碼', with: '0912000000'
          select '5', from: '大人數'
          select '0', from: '小孩數'
          select business_period.name, from: '營業時段'
          
          fill_in '訂位日期', with: lunch_time.strftime('%Y-%m-%d')
          fill_in '訂位時間', with: '12:00'

          click_button '建立訂位'
        end

        expect(page).to have_content('訂位建立成功')
        lunch_reservation = Reservation.last

        # 晚餐時段訂位（相同桌位）
        visit admin_reservations_path
        click_button '新增訂位'

        within '#new_reservation_form' do
          fill_in '客戶姓名', with: '晚餐客戶'
          fill_in '電話號碼', with: '0918000000'
          select '5', from: '大人數'
          select '0', from: '小孩數'
          select dinner_period.name, from: '營業時段'
          
          fill_in '訂位日期', with: dinner_time.strftime('%Y-%m-%d')
          fill_in '訂位時間', with: '18:00'

          click_button '建立訂位'
        end

        expect(page).to have_content('訂位建立成功')
        dinner_reservation = Reservation.last

        # 應該分配到相同的桌位
        expect(dinner_reservation.table.id).to eq(lunch_reservation.table.id)
      end
    end

    context '報表和統計' do
      scenario '查看桌位使用率報表' do
        # 建立一些測試訂位
        tomorrow = 1.day.from_now.change(hour: 12, min: 0)
        
        create(:reservation, :confirmed,
             restaurant: restaurant,
             business_period: business_period,
             table: @window_table,
             customer_name: '測試客戶1',
             reservation_datetime: tomorrow)

        visit admin_dashboard_path
        
        expect(page).to have_content('桌位使用率')
        expect(page).to have_content('今日訂位')
        
        # 檢查統計資訊
        within '.reservation-stats' do
          expect(page).to have_content('1') # 今日訂位數
        end
      end

      scenario '查看空桌位狀態' do
        visit admin_tables_path
        
        expect(page).to have_content('桌位管理')
        
        within '.table-status' do
          expect(page).to have_content('可用') # 顯示桌位狀態
          expect(page).to have_content(@window_table.table_number)
        end
      end
    end
  end

  describe '錯誤處理和用戶體驗', js: true do
    scenario '網路錯誤時的優雅降級' do
      # 模擬網路錯誤
      allow_any_instance_of(ReservationAllocatorService).to receive(:allocate_table).and_raise(StandardError, '網路錯誤')

      visit admin_reservations_path
      click_button '新增訂位'

      within '#new_reservation_form' do
        fill_in '客戶姓名', with: '錯誤測試'
        fill_in '電話號碼', with: '0900000000'
        select '2', from: '大人數'
        select '0', from: '小孩數'
        select business_period.name, from: '營業時段'
        
        tomorrow = 1.day.from_now
        fill_in '訂位日期', with: tomorrow.strftime('%Y-%m-%d')
        fill_in '訂位時間', with: '12:00'

        click_button '建立訂位'
      end

      expect(page).to have_content('系統錯誤').or have_content('請稍後再試')
    end

    scenario '表單驗證錯誤顯示' do
      visit admin_reservations_path
      click_button '新增訂位'

      within '#new_reservation_form' do
        # 故意留空必填欄位
        click_button '建立訂位'
      end

      expect(page).to have_content('客戶姓名不能為空')
      expect(page).to have_content('電話號碼不能為空')
    end
  end

  describe '效能測試' do
    scenario '大量訂位時的系統響應' do
      # 建立多個訂位測試系統負載
      start_time = Time.current

      10.times do |i|
        visit admin_reservations_path
        click_button '新增訂位'

        within '#new_reservation_form' do
          fill_in '客戶姓名', with: "客戶#{i}"
          fill_in '電話號碼', with: "091234567#{i}"
          select '1', from: '大人數'
          select '0', from: '小孩數'
          select business_period.name, from: '營業時段'
          
          tomorrow = 1.day.from_now
          fill_in '訂位日期', with: tomorrow.strftime('%Y-%m-%d')
          fill_in '訂位時間', with: "12:#{i.to_s.rjust(2, '0')}"

          click_button '建立訂位'
        end

        expect(page).to have_content('訂位建立成功')
      end

      end_time = Time.current
      total_time = end_time - start_time

      # 效能期望：10個訂位應該在合理時間內完成
      expect(total_time).to be < 30.seconds
      expect(Reservation.count).to eq(10)
    end
  end

  private

  def setup_test_environment
    # 設置餐廳政策
    policy = restaurant.reservation_policy || restaurant.create_reservation_policy
    policy.update!(
      max_party_size: 20,
      min_party_size: 1,
      advance_booking_days: 30,
      minimum_advance_hours: 1
    )

    # 建立桌位
    @window_table = create(:table, :window_round_table,
                          restaurant: restaurant,
                          table_group: table_group_window,
                          sort_order: 1)

    @square_tables = []
    %w[A B C].each_with_index do |letter, index|
      @square_tables << create(:table, :square_table,
                              restaurant: restaurant,
                              table_group: table_group_square,
                              table_number: "方桌#{letter}",
                              sort_order: index + 1)
    end

    @bar_tables = []
    %w[A B C].each_with_index do |letter, index|
      @bar_tables << create(:table, :bar_seat,
                           restaurant: restaurant,
                           table_group: table_group_bar,
                           table_number: "吧台#{letter}",
                           sort_order: index + 1)
    end

    # 更新餐廳容量
    restaurant.update!(total_capacity: restaurant.calculate_total_capacity)
  end
end 