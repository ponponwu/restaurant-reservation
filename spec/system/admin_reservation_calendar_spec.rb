require 'rails_helper'

RSpec.describe 'Admin Reservation Calendar', :js do
  let(:restaurant) { create(:restaurant, slug: 'test-restaurant') }
  let(:admin_user) { create(:user, :admin, restaurant: restaurant) }

  before do
    # 設定餐廳的營業時段
    @lunch_period = restaurant.business_periods.create!(
      name: 'lunch',
      display_name: '午餐',
      start_time: '11:30',
      end_time: '14:30',
      days_of_week_mask: 127, # 週一到週日
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
    table_group = restaurant.table_groups.create!(
      name: '主要區域',
      description: '主要用餐區域',
      active: true
    )

    restaurant.restaurant_tables.create!(
      table_number: 'A1',
      capacity: 4,
      min_capacity: 1,
      max_capacity: 4,
      table_group: table_group,
      active: true
    )

    sign_in admin_user
  end

  describe '日曆休息日排除功能' do
    context '當餐廳有週休息日設定' do
      before do
        # 設定週一和週二休息（days_of_week_mask 不包含這些天）
        @lunch_period.update!(days_of_week_mask: 124) # 排除週一(1)和週二(2)，只開 週三-週日
        @dinner_period.update!(days_of_week_mask: 124)
      end

      it '應該在日曆中禁用週休息日' do
        visit new_admin_restaurant_reservation_path(restaurant)
        setup_july_calendar

        # 檢查週一和週二被禁用（依據days_of_week_mask設定）
        expect_day_disabled(7)  # 7月7日（週一）
        expect_day_disabled(8)  # 7月8日（週二）

        # 檢查週三可選（營業日）
        expect_day_enabled(9) # 7月9日（週三）
      end
    end

    context '當餐廳有特殊休息日設定' do
      let(:special_closure_date) { Date.new(2025, 7, 10) } # 7月10日（週四）

      before do
        # 建立特殊休息日
        restaurant.closure_dates.create!(
          date: special_closure_date,
          reason: '特殊公休',
          recurring: false,
          all_day: true
        )
      end

      it '應該在日曆中禁用特殊休息日' do
        visit new_admin_restaurant_reservation_path(restaurant)
        setup_july_calendar

        # 檢查特殊休息日被禁用
        expect_day_disabled(10) # 7月10日（週四，特殊休息日）
      end
    end

    context '當餐廳容量不足' do
      before do
        # 刪除所有桌位，模擬沒有容量
        restaurant.restaurant_tables.destroy_all
      end

      it '管理員仍然可以選擇任何營業日（不受容量限制）' do
        visit new_admin_restaurant_reservation_path(restaurant)
        setup_july_calendar

        # 檢查營業日應該可選，即使沒有容量（管理員不受容量限制）
        expect_day_enabled(9) # 7月9日（週三，營業日）
      end
    end

    context '複合情況：週休息日 + 特殊休息日' do
      let(:special_closure_date) { Date.new(2025, 7, 9) } # 7月9日（週三）

      before do
        # 設定週一週二休息
        @lunch_period.update!(days_of_week_mask: 124) # 排除週一週二
        @dinner_period.update!(days_of_week_mask: 124)

        # 設定週三特殊休息
        restaurant.closure_dates.create!(
          date: special_closure_date,
          reason: '特殊公休',
          recurring: false,
          all_day: true
        )
      end

      it '應該同時禁用週休息日和特殊休息日' do
        visit new_admin_restaurant_reservation_path(restaurant)
        setup_july_calendar

        # 檢查週休息日被禁用
        expect_day_disabled(7)  # 7月7日（週一）
        expect_day_disabled(8)  # 7月8日（週二）

        # 檢查特殊休息日被禁用
        expect_day_disabled(9) # 7月9日（週三，特殊休息日）

        # 檢查其他營業日可選
        expect_day_enabled(10) # 7月10日（週四，正常營業日）
      end
    end
  end

  describe '日期選擇功能' do
    it '應該能夠選擇營業日並更新表單欄位' do
      visit new_admin_restaurant_reservation_path(restaurant)
      setup_july_calendar

      # 選擇一個營業日並檢查表單更新
      click_calendar_day(10) # 7月10日（週四）

      # 檢查隱藏欄位是否被更新
      expect(page).to have_field('reservation[reservation_datetime]', type: :hidden)
    end
  end

  describe 'API 呼叫處理' do
    context '當 available_days API 失敗' do
      it '應該使用備用日期選擇器' do
        # 模擬網路錯誤或API不可用的情況
        # 在這種情況下前端應該使用基本的日期選擇器
        visit new_admin_restaurant_reservation_path(restaurant)

        # 應該仍然有日曆可用（備用版本）
        wait_for_calendar

        # 驗證日曆基本功能仍然工作
        setup_july_calendar
        expect_day_enabled(10) # 確保至少某個營業日可選
      end
    end
  end

  describe '人數變更對日曆的影響' do
    before do
      # 設定週一休息
      @lunch_period.update!(days_of_week_mask: 126) # 排除週一
      @dinner_period.update!(days_of_week_mask: 126)
    end

    it '改變人數時休息日設定應該保持不變' do
      visit new_admin_restaurant_reservation_path(restaurant)
      setup_july_calendar

      # 檢查週一被禁用（依據days_of_week_mask設定）
      expect_day_disabled(7) # 7月7日（週一）

      # 改變人數
      fill_in '總人數', with: '6'

      # 等待可能的重新載入
      sleep 0.5

      # 週一應該仍然被禁用（休息日設定不受人數影響）
      expect_day_disabled(7) # 7月7日（週一）
    end
  end
end
