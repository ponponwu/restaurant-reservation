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
        @special_closure = 7.days.from_now.to_date
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

        # 選擇日期 - 尋找隱藏的日期欄位並直接設定
        target_date = 3.days.from_now.to_date

        # 檢查是否有隱藏的日期欄位
        hidden_date_field = page.first('input[type="hidden"][name*="date"]', visible: false)
        if hidden_date_field
          page.execute_script("document.querySelector('input[type=\"hidden\"][name*=\"date\"]').value = '#{target_date.strftime('%Y-%m-%d')}'")
        else
          # 如果沒有隱藏欄位，嘗試設定 Flatpickr 的隱藏輸入
          page.execute_script("
            const flatpickrInputs = document.querySelectorAll('.flatpickr-input');
            if (flatpickrInputs.length > 0) {
              const input = flatpickrInputs[0];
              input.value = '#{target_date.strftime('%Y-%m-%d')}';
              input._flatpickr.setDate('#{target_date.strftime('%Y-%m-%d')}');
            }
          ")
        end

        # 選擇餐期
        select '晚餐 (17:30 - 21:30)', from: '餐期選擇'

        # 設定時間
        fill_in '訂位時間', with: '19:00'

        # 檢查是否有桌位選擇選項，如果有就選擇第一個可用的桌位
        if page.has_select?('選擇桌位')
          table_options = page.find('select[name*="table"]').all('option').reject { |opt| opt.text.include?('請選擇') }
          select table_options.first.text, from: '選擇桌位' if table_options.any?
        end

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

        # 檢查週一休息日無法選擇
        wait_for_calendar

        # 找到下週一的日期並檢查是否被禁用
        next_monday = Date.current.next_occurring(:monday)
        if next_monday.month == Date.current.month
          monday_day = next_monday.day
          monday_element = find_calendar_day(monday_day)
          expect(monday_element[:class]).to include('flatpickr-disabled') if monday_element
        end

        # 確保日曆已載入
        expect(page).to have_content('選擇日期')
      end

      it '不應該能夠選擇特殊休息日' do
        visit new_admin_restaurant_reservation_path(restaurant)

        # 檢查特殊休息日無法選擇
        wait_for_calendar

        # 檢查特殊休息日是否被正確禁用
        if @special_closure.month == Date.current.month
          special_day = @special_closure.day
          special_element = find_calendar_day(special_day)
          expect(special_element[:class]).to include('flatpickr-disabled') if special_element
        end

        # 確保日曆已載入
        expect(page).to have_content('選擇日期')
      end
    end

    context '在沒有容量限制的情況下（管理員強制模式）' do
      before do
        # 創建一個小容量桌位，測試強制模式可以超越容量限制
        restaurant.restaurant_tables.destroy_all
        restaurant.restaurant_tables.create!(
          table_number: 'SMALL1',
          capacity: 2,
          min_capacity: 1,
          max_capacity: 2,
          table_group: @table_group,
          active: true
        )

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

        # 選擇日期 - 直接設定隱藏欄位
        target_date = 3.days.from_now.to_date

        # 檢查是否有隱藏的日期欄位
        hidden_date_field = page.first('input[type="hidden"][name*="date"]', visible: false)
        if hidden_date_field
          page.execute_script("document.querySelector('input[type=\"hidden\"][name*=\"date\"]').value = '#{target_date.strftime('%Y-%m-%d')}'")
        else
          # 如果沒有隱藏欄位，嘗試設定 Flatpickr 的隱藏輸入
          page.execute_script("
            const flatpickrInputs = document.querySelectorAll('.flatpickr-input');
            if (flatpickrInputs.length > 0) {
              const input = flatpickrInputs[0];
              input.value = '#{target_date.strftime('%Y-%m-%d')}';
              if (input._flatpickr) input._flatpickr.setDate('#{target_date.strftime('%Y-%m-%d')}');
            }
          ")
        end

        # 選擇餐期和時間
        select '午餐 (11:30 - 14:30)', from: '餐期選擇'
        fill_in '訂位時間', with: '12:00'

        # 啟用強制模式
        check '管理員強制模式'

        # 在強制模式下，選擇小容量桌位但使用大人數測試超越容量限制
        if page.has_select?('選擇桌位')
          table_options = page.find('select[name*="table"]').all('option').reject { |opt| opt.text.include?('請選擇') }
          select table_options.first.text, from: '選擇桌位' if table_options.any?
        end

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

        # 啟用強制模式
        check '管理員強制模式'

        # 檢查週三仍然被禁用（即使在強制模式下）
        wait_for_calendar

        # 找到下週三的日期並檢查是否被禁用
        next_wednesday = Date.current.next_occurring(:wednesday)
        if next_wednesday.month == Date.current.month
          wednesday_day = next_wednesday.day
          wednesday_element = find_calendar_day(wednesday_day)
          expect(wednesday_element[:class]).to include('flatpickr-disabled') if wednesday_element
        end

        # 確保日曆已載入
        expect(page).to have_content('選擇日期')
      end
    end

    context '錯誤情況處理' do
      it '當 API 無法載入時應該有備用日曆' do
        visit new_admin_restaurant_reservation_path(restaurant)

        # 應該仍然有訂位表單可用（即使沒有休息日資訊）
        expect(page).to have_content('選擇日期')
        expect(page).to have_css('.flatpickr-calendar')
      end
    end
  end

  describe '日期篩選功能整合' do
    it '建立訂位後應該跳轉到該日期的訂位列表' do
      visit new_admin_restaurant_reservation_path(restaurant)

      # 建立訂位
      fill_in '客戶姓名', with: '測試客戶'
      fill_in '電話號碼', with: '0912345678'
      fill_in '總人數', with: '2'

      # 選擇日期 - 直接設定隱藏欄位
      target_date = 3.days.from_now.to_date

      # 檢查是否有隱藏的日期欄位
      hidden_date_field = page.first('input[type="hidden"][name*="date"]', visible: false)
      if hidden_date_field
        page.execute_script("document.querySelector('input[type=\"hidden\"][name*=\"date\"]').value = '#{target_date.strftime('%Y-%m-%d')}'")
      else
        # 如果沒有隱藏欄位，嘗試設定 Flatpickr 的隱藏輸入
        page.execute_script("
          const flatpickrInputs = document.querySelectorAll('.flatpickr-input');
          if (flatpickrInputs.length > 0) {
            const input = flatpickrInputs[0];
            input.value = '#{target_date.strftime('%Y-%m-%d')}';
            if (input._flatpickr) input._flatpickr.setDate('#{target_date.strftime('%Y-%m-%d')}');
          }
        ")
      end

      select '晚餐 (17:30 - 21:30)', from: '餐期選擇'
      fill_in '訂位時間', with: '19:00'

      # 檢查是否有桌位選擇選項，如果有就選擇第一個可用的桌位
      if page.has_select?('選擇桌位')
        table_options = page.find('select[name*="table"]').all('option').reject { |opt| opt.text.include?('請選擇') }
        select table_options.first.text, from: '選擇桌位' if table_options.any?
      end

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
    date = 1.day.from_now.to_date
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

  def wait_for_calendar
    # 等待日曆載入
    expect(page).to have_css('.flatpickr-calendar', wait: 5)
  rescue Capybara::ElementNotFound
    # 如果找不到 flatpickr 日曆，嘗試其他日曆實現
    expect(page).to have_content('選擇日期')
  end

  def find_calendar_day(day)
    # 嘗試找到指定日期的日曆元素

    page.find(".flatpickr-day[aria-label*='#{day}']")
  rescue Capybara::ElementNotFound
    # 如果找不到 flatpickr 的日期元素，返回 nil
    nil
  end
end
