require 'rails_helper'

RSpec.describe 'Frontend Calendar Integration', :js do
  let(:restaurant) { create(:restaurant, name: '測試餐廳') }
  let(:business_period) { create(:business_period, restaurant: restaurant, name: '晚餐時段') }
  let(:table_group) { create(:table_group, restaurant: restaurant) }
  let(:table) { create(:table, restaurant: restaurant, table_group: table_group) }

  before do
    business_period
    table
    restaurant.reservation_policy.update!(reservation_enabled: true)

    # Mock availability services
    allow_any_instance_of(AvailabilityService).to receive(:get_available_slots_by_period).and_return([
                                                                                                       {
                                                                                                         period_name: '晚餐時段',
                                                                                                         time: '18:00',
                                                                                                         available: true,
                                                                                                         business_period_id: business_period.id
                                                                                                       }
                                                                                                     ])
  end

  describe 'Calendar date selection with closure dates' do
    context 'with weekly closure days' do
      before do
        # 設定週一休息
        business_period.update!(days_of_week_mask: 126) # 排除週一(1)
      end

      it 'disables weekly closure days in calendar' do
        visit restaurant_public_path(restaurant.slug)

        # 選擇人數
        select '2 人', from: 'reservation[adult_count]'

        # 點擊日期選擇器
        find('input[data-reservation-target="date"]').click

        # 等待日曆載入
        expect(page).to have_css('.flatpickr-calendar', wait: 5)

        # 檢查下個週一是否被禁用
        next_monday = Date.current.next_occurring(:monday)
        within('.flatpickr-calendar') do
          monday_element = find(".flatpickr-day[aria-label*='#{next_monday.strftime('%B %-d, %Y')}']", wait: 3)
          expect(monday_element).to have_css('.flatpickr-disabled')
        end

        # 檢查週二是否可選
        next_tuesday = Date.current.next_occurring(:tuesday)
        within('.flatpickr-calendar') do
          tuesday_element = find(".flatpickr-day[aria-label*='#{next_tuesday.strftime('%B %-d, %Y')}']", wait: 3)
          expect(tuesday_element).not_to have_css('.flatpickr-disabled')
        end
      end
    end

    context 'with special closure dates' do
      let(:special_closure_date) { Date.current + 7.days }

      before do
        restaurant.closure_dates.create!(
          date: special_closure_date,
          reason: '特殊公休',
          all_day: true
        )
      end

      it 'disables special closure dates in calendar' do
        visit restaurant_public_path(restaurant.slug)

        select '2 人', from: 'reservation[adult_count]'
        find('input[data-reservation-target="date"]').click

        expect(page).to have_css('.flatpickr-calendar', wait: 5)

        within('.flatpickr-calendar') do
          closure_element = find(".flatpickr-day[aria-label*='#{special_closure_date.strftime('%B %-d, %Y')}']", wait: 3)
          expect(closure_element).to have_css('.flatpickr-disabled')
        end
      end
    end

    context 'with capacity limitations' do
      before do
        # 移除所有桌位，模擬沒有容量
        restaurant.restaurant_tables.destroy_all
      end

      it 'disables all dates when no capacity available' do
        visit restaurant_public_path(restaurant.slug)

        select '8 人', from: 'reservation[adult_count]' # 超過容量的人數

        find('input[data-reservation-target="date"]').click
        expect(page).to have_css('.flatpickr-calendar', wait: 5)

        # 前台應該因為沒有容量而禁用所有日期
        within('.flatpickr-calendar') do
          tomorrow = Date.current + 1.day
          tomorrow_element = find(".flatpickr-day[aria-label*='#{tomorrow.strftime('%B %-d, %Y')}']", wait: 3)
          expect(tomorrow_element).to have_css('.flatpickr-disabled')
        end
      end
    end
  end

  describe 'Real-time time slot updates' do
    it 'updates available time slots when date changes' do
      visit restaurant_public_path(restaurant.slug)

      select '2 人', from: 'reservation[adult_count]'

      # 選擇日期
      find('input[data-reservation-target="date"]').click
      sleep 1

      within('.flatpickr-calendar') do
        find('.flatpickr-day.today').click
      end

      # 等待時間槽載入
      expect(page).to have_content('晚餐時段', wait: 10)
      expect(page).to have_button('18:00', wait: 5)
    end

    it 'shows no available times message when restaurant is closed' do
      # Mock 餐廳當天公休
      allow_any_instance_of(Restaurant).to receive(:closed_on_date?).and_return(true)

      visit restaurant_public_path(restaurant.slug)

      select '2 人', from: 'reservation[adult_count]'

      find('input[data-reservation-target="date"]').click
      sleep 1

      within('.flatpickr-calendar') do
        find('.flatpickr-day.today').click
      end

      expect(page).to have_content('餐廳當天公休', wait: 5)
    end

    it 'shows no available times when all slots are full' do
      # Mock 沒有可用時間槽
      allow_any_instance_of(AvailabilityService).to receive(:get_available_slots_by_period).and_return([])

      visit restaurant_public_path(restaurant.slug)

      select '2 人', from: 'reservation[adult_count]'

      find('input[data-reservation-target="date"]').click
      sleep 1

      within('.flatpickr-calendar') do
        find('.flatpickr-day.today').click
      end

      expect(page).to have_content('該日無可用時間', wait: 5)
    end
  end

  describe 'Dynamic party size adjustment' do
    it 'adjusts child options based on adult count' do
      visit restaurant_public_path(restaurant.slug)

      adult_select = find('[data-reservation-target="adultCount"]')
      child_select = find('[data-reservation-target="childCount"]')

      # 初始狀態：2大人，小孩可選0-4
      expect(adult_select.value).to eq('2')
      child_options = child_select.all('option').map(&:value)
      expect(child_options).to eq(%w[0 1 2 3 4])

      # 改為4大人，小孩選項應該變為0-2
      adult_select.select('4')
      sleep 1

      child_options = child_select.all('option').map(&:value)
      expect(child_options).to eq(%w[0 1 2])
    end

    it 'prevents total party size from exceeding maximum' do
      visit restaurant_public_path(restaurant.slug)

      adult_select = find('[data-reservation-target="adultCount"]')
      child_select = find('[data-reservation-target="childCount"]')

      # 選擇3大人3小孩 = 6人總計
      adult_select.select('3')
      sleep 0.5
      child_select.select('3')
      sleep 1

      # 嘗試增加大人數到5，小孩數應該自動調整
      adult_select.select('5')
      sleep 1

      expect(child_select.value).to eq('1') # 調整為1，總計6人
    end
  end

  describe 'Error handling and edge cases' do
    it 'handles API failures gracefully' do
      # Mock API 失敗
      allow_any_instance_of(RestaurantsController).to receive(:available_slots).and_raise(StandardError.new('API Error'))

      visit restaurant_public_path(restaurant.slug)

      select '2 人', from: 'reservation[adult_count]'

      find('input[data-reservation-target="date"]').click
      sleep 1

      within('.flatpickr-calendar') do
        find('.flatpickr-day.today').click
      end

      # 應該顯示錯誤訊息而不是崩潰
      expect(page).to have_content('載入時間時發生錯誤', wait: 5)
    end

    it 'validates required fields before submission' do
      visit restaurant_public_path(restaurant.slug)

      # 跳過選擇，直接訪問訂位表單
      visit new_restaurant_reservation_path(restaurant.slug, {
                                              date: Date.current.strftime('%Y-%m-%d'),
                                              adults: 2,
                                              children: 0,
                                              time: '18:00',
                                              period_id: business_period.id
                                            })

      # 不填寫任何欄位，直接提交
      click_button '送出預約申請'

      # 應該顯示驗證錯誤
      expect(page).to have_content("can't be blank")
    end

    it 'handles table allocation failure' do
      # Mock 桌位分配失敗
      allow_any_instance_of(ReservationAllocatorService).to receive(:allocate_table).and_return(nil)

      visit restaurant_public_path(restaurant.slug)

      select '2 人', from: 'reservation[adult_count]'

      find('input[data-reservation-target="date"]').click
      sleep 1

      within('.flatpickr-calendar') do
        find('.flatpickr-day.today').click
      end

      click_button '18:00' if page.has_button?('18:00')

      fill_in '聯絡人姓名', with: '測試客戶'
      fill_in '聯絡電話', with: '0912345678'
      fill_in '電子郵件', with: 'test@example.com'

      click_button '送出預約申請'

      expect(page).to have_content('該時段已無可用桌位')
    end
  end

  describe 'Mobile responsiveness' do
    before do
      # 設定手機視窗大小
      page.driver.browser.manage.window.resize_to(375, 667)
    end

    after do
      # 恢復桌面視窗大小
      page.driver.browser.manage.window.resize_to(1024, 768)
    end

    it 'calendar works on mobile devices' do
      visit restaurant_public_path(restaurant.slug)

      # 在手機上選擇人數
      select '2 人', from: 'reservation[adult_count]'

      # 點擊日期選擇器
      find('input[data-reservation-target="date"]').click

      # 日曆應該正常顯示
      expect(page).to have_css('.flatpickr-calendar', wait: 5)

      # 可以選擇日期
      within('.flatpickr-calendar') do
        find('.flatpickr-day.today').click
      end

      # 時間選項應該正常顯示
      expect(page).to have_button('18:00', wait: 5)
    end
  end

  describe 'Accessibility features' do
    it 'calendar is keyboard navigable' do
      visit restaurant_public_path(restaurant.slug)

      select '2 人', from: 'reservation[adult_count]'

      # 使用鍵盤導航到日期欄位
      date_input = find('input[data-reservation-target="date"]')
      date_input.send_keys(:tab)
      date_input.send_keys(:enter)

      expect(page).to have_css('.flatpickr-calendar', wait: 5)

      # 可以使用方向鍵導航
      date_input.send_keys(:arrow_right)
      date_input.send_keys(:enter)

      expect(page).to have_button('18:00', wait: 5)
    end

    it 'has proper ARIA labels' do
      visit restaurant_public_path(restaurant.slug)

      # 檢查必要的ARIA標籤
      expect(page).to have_css('[aria-label]')
      expect(page).to have_css('[role="button"]')
    end
  end
end
