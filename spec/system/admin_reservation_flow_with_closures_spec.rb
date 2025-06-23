require 'rails_helper'

RSpec.describe 'Admin Reservation Flow with Closure Dates', :js do
  let(:restaurant) { create(:restaurant, slug: 'test-restaurant') }
  let(:admin_user) { create(:user, :admin, restaurant: restaurant) }

  before do
    # 設定餐廳的營業時段
    @lunch_period = restaurant.business_periods.create!(
      name: 'lunch',
      display_name: '午餐',
      start_time: '11:30',
      end_time: '14:30',
      days_of_week_mask: 127,
      active: true
    )

    @dinner_period = restaurant.business_periods.create!(
      name: 'dinner',
      display_name: '晚餐',
      start_time: '17:30',
      end_time: '21:30',
      days_of_week_mask: 127,
      active: true
    )

    # 設定桌位群組和桌位
    @table_group = restaurant.table_groups.create!(
      name: '主要區域',
      description: '主要用餐區域',
      active: true
    )

    @table = restaurant.restaurant_tables.create!(
      table_number: 'A1',
      capacity: 4,
      min_capacity: 1,
      max_capacity: 4,
      table_group: @table_group,
      active: true
    )

    sign_in admin_user
  end

  describe '完整的後台訂位流程' do
    context '在有休息日設定的情況下' do
      before do
        # 設定週一休息
        @lunch_period.update!(days_of_week_mask: 126) # 排除週一
        @dinner_period.update!(days_of_week_mask: 126)

        # 設定特殊休息日
        @special_closure = Date.current + 7.days
        restaurant.closure_dates.create!(
          date: @special_closure,
          reason: '特殊公休',
          recurring: false,
          all_day: true
        )
      end

      it '應該能夠在營業日成功建立訂位' do
        visit new_admin_restaurant_reservation_path(restaurant)

        # 等待頁面載入
        expect(page).to have_content('建立訂位')

        # 填寫客戶資訊
        fill_in '客戶姓名', with: '測試客戶'
        fill_in '電話號碼', with: '0912345678'
        fill_in '電子郵件', with: 'test@example.com'

        # 設定人數
        fill_in '總人數', with: '2'

        # 等待日曆載入
        expect(page).to have_css('.flatpickr-calendar', wait: 10)

        # 選擇一個營業日（避開週一和特殊休息日）
        target_date = find_next_business_day

        within '.flatpickr-calendar' do
          # 確認目標日期不是禁用的
          date_element = find(".flatpickr-day[aria-label*='#{target_date.strftime('%B %-d, %Y')}']", wait: 5)
          expect(date_element).not_to have_css('.flatpickr-disabled')

          # 點擊日期
          date_element.click
        end

        # 選擇餐期
        select '晚餐 (17:30 - 21:30)', from: '餐期選擇'

        # 設定時間
        fill_in '訂位時間', with: '19:00'

        # 提交表單
        click_button '建立訂位'

        # 驗證成功訊息和跳轉
        expect(page).to have_content('訂位建立成功')
        expect(page).to have_current_path(admin_restaurant_reservations_path(restaurant), ignore_query: true)

        # 驗證 URL 包含日期參數
        expect(current_url).to include("date_filter=#{target_date.strftime('%Y-%m-%d')}")

        # 驗證訂位已建立
        reservation = restaurant.reservations.last
        expect(reservation.customer_name).to eq('測試客戶')
        expect(reservation.reservation_datetime.to_date).to eq(target_date)
        expect(reservation.business_period).to eq(@dinner_period)
      end

      it '不應該能夠選擇週休息日' do
        visit new_admin_restaurant_reservation_path(restaurant)

        # 等待日曆載入
        expect(page).to have_css('.flatpickr-calendar', wait: 10)

        # 檢查下個週一應該被禁用
        next_monday = Date.current.next_occurring(:monday)

        within '.flatpickr-calendar' do
          monday_element = find(".flatpickr-day[aria-label*='#{next_monday.strftime('%B %-d, %Y')}']", wait: 5)
          expect(monday_element).to have_css('.flatpickr-disabled')

          # 嘗試點擊應該無效
          monday_element.click

          # 隱藏欄位應該還是空的
          expect(page).to have_field('reservation[reservation_datetime]', with: '', type: :hidden)
        end
      end

      it '不應該能夠選擇特殊休息日' do
        visit new_admin_restaurant_reservation_path(restaurant)

        # 等待日曆載入
        expect(page).to have_css('.flatpickr-calendar', wait: 10)

        within '.flatpickr-calendar' do
          closure_element = find(".flatpickr-day[aria-label*='#{@special_closure.strftime('%B %-d, %Y')}']", wait: 5)
          expect(closure_element).to have_css('.flatpickr-disabled')
        end
      end
    end

    context '在沒有容量限制的情況下（管理員強制模式）' do
      before do
        # 刪除所有桌位，模擬沒有容量
        restaurant.restaurant_tables.destroy_all

        # 設定週三休息
        @lunch_period.update!(days_of_week_mask: 119) # 排除週三(4)
        @dinner_period.update!(days_of_week_mask: 119)
      end

      it '應該能夠在營業日強制建立訂位（即使沒有容量）' do
        visit new_admin_restaurant_reservation_path(restaurant)

        # 填寫客戶資訊
        fill_in '客戶姓名', with: '強制訂位客戶'
        fill_in '電話號碼', with: '0987654321'
        fill_in '總人數', with: '8' # 大人數，肯定超過容量

        # 等待日曆載入
        expect(page).to have_css('.flatpickr-calendar', wait: 10)

        # 選擇營業日（非週三）
        target_date = find_next_business_day_excluding([3]) # 排除週三

        within '.flatpickr-calendar' do
          date_element = find(".flatpickr-day[aria-label*='#{target_date.strftime('%B %-d, %Y')}']", wait: 5)
          expect(date_element).not_to have_css('.flatpickr-disabled')
          date_element.click
        end

        # 選擇餐期和時間
        select '午餐 (11:30 - 14:30)', from: '餐期選擇'
        fill_in '訂位時間', with: '12:00'

        # 啟用強制模式
        check '管理員強制模式'

        # 提交表單
        click_button '建立訂位'

        # 應該成功建立（即使沒有容量）
        expect(page).to have_content('訂位建立成功')

        # 驗證訂位已建立且標記為強制模式
        reservation = restaurant.reservations.last
        expect(reservation.customer_name).to eq('強制訂位客戶')
        expect(reservation.party_size).to eq(8)
        expect(reservation.admin_override).to be true
      end

      it '仍然不能選擇休息日（即使在強制模式下）' do
        visit new_admin_restaurant_reservation_path(restaurant)

        # 等待日曆載入
        expect(page).to have_css('.flatpickr-calendar', wait: 10)

        # 啟用強制模式
        check '管理員強制模式'

        # 檢查週三仍然被禁用
        next_wednesday = Date.current.next_occurring(:wednesday)

        within '.flatpickr-calendar' do
          wednesday_element = find(".flatpickr-day[aria-label*='#{next_wednesday.strftime('%B %-d, %Y')}']", wait: 5)
          expect(wednesday_element).to have_css('.flatpickr-disabled')
        end
      end
    end

    context '錯誤情況處理' do
      it '當 API 無法載入時應該有備用日曆' do
        # 模擬 API 失敗
        page.driver.browser.network_conditions = { offline: true }

        visit new_admin_restaurant_reservation_path(restaurant)

        # 應該仍然有日曆可用（即使沒有休息日資訊）
        expect(page).to have_css('.flatpickr-calendar', wait: 10)

        # 恢復網路
        page.driver.browser.network_conditions = { offline: false }
      end
    end
  end

  describe '日期篩選功能整合' do
    it '建立訂位後應該跳轉到該日期的訂位列表' do
      target_date = Date.current + 2.days

      visit new_admin_restaurant_reservation_path(restaurant)

      # 建立訂位
      fill_in '客戶姓名', with: '測試客戶'
      fill_in '電話號碼', with: '0912345678'
      fill_in '總人數', with: '2'

      # 等待並選擇日期
      expect(page).to have_css('.flatpickr-calendar', wait: 10)

      within '.flatpickr-calendar' do
        date_element = find(".flatpickr-day[aria-label*='#{target_date.strftime('%B %-d, %Y')}']", wait: 5)
        date_element.click
      end

      select '晚餐 (17:30 - 21:30)', from: '餐期選擇'
      fill_in '訂位時間', with: '19:00'

      click_button '建立訂位'

      # 驗證跳轉到正確的日期篩選頁面
      expect(current_url).to include("date_filter=#{target_date.strftime('%Y-%m-%d')}")

      # 驗證頁面顯示該日期的訂位
      expect(page).to have_content(target_date.strftime('%Y年%m月%d日'))
      expect(page).to have_content('測試客戶')
    end
  end

  private

  # 預設排除週一
  def find_next_business_day(exclude_weekdays = [1])
    date = Date.current + 1.day
    30.times do # 最多檢查30天
      weekday = date.wday
      is_special_closure = restaurant.closure_dates.exists?(date: date)

      return date unless exclude_weekdays.include?(weekday) || is_special_closure

      date += 1.day
    end

    raise '找不到合適的營業日'
  end

  def find_next_business_day_excluding(exclude_weekdays)
    find_next_business_day(exclude_weekdays)
  end
end
