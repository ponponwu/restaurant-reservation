require 'rails_helper'

RSpec.describe 'Admin Reservation Calendar', type: :system, js: true do
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

        # 等待日曆載入
        expect(page).to have_css('.flatpickr-calendar', wait: 5)

        # 檢查週一和週二的日期應該被禁用
        next_monday = Date.current.next_occurring(:monday)
        next_tuesday = Date.current.next_occurring(:tuesday)
        
        within '.flatpickr-calendar' do
          monday_element = find(".flatpickr-day[aria-label*='#{next_monday.strftime('%B %-d, %Y')}']", wait: 3)
          tuesday_element = find(".flatpickr-day[aria-label*='#{next_tuesday.strftime('%B %-d, %Y')}']", wait: 3)
          
          expect(monday_element).to have_css('.flatpickr-disabled')
          expect(tuesday_element).to have_css('.flatpickr-disabled')
        end

        # 檢查其他日期應該可選
        next_wednesday = Date.current.next_occurring(:wednesday)
        within '.flatpickr-calendar' do
          wednesday_element = find(".flatpickr-day[aria-label*='#{next_wednesday.strftime('%B %-d, %Y')}']", wait: 3)
          expect(wednesday_element).not_to have_css('.flatpickr-disabled')
        end
      end
    end

    context '當餐廳有特殊休息日設定' do
      let(:special_closure_date) { Date.current + 7.days }
      
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

        # 等待日曆載入
        expect(page).to have_css('.flatpickr-calendar', wait: 5)

        # 檢查特殊休息日應該被禁用
        within '.flatpickr-calendar' do
          closure_element = find(".flatpickr-day[aria-label*='#{special_closure_date.strftime('%B %-d, %Y')}']", wait: 3)
          expect(closure_element).to have_css('.flatpickr-disabled')
        end
      end
    end

    context '當餐廳容量不足' do
      before do
        # 刪除所有桌位，模擬沒有容量
        restaurant.restaurant_tables.destroy_all
      end

      it '管理員仍然可以選擇任何營業日（不受容量限制）' do
        visit new_admin_restaurant_reservation_path(restaurant)

        # 等待日曆載入
        expect(page).to have_css('.flatpickr-calendar', wait: 5)

        # 管理員應該仍然可以選擇營業日，即使沒有容量
        tomorrow = Date.current + 1.day
        
        # 確保明天是營業日（不是週休息日）
        unless tomorrow.monday? || tomorrow.tuesday?
          within '.flatpickr-calendar' do
            tomorrow_element = find(".flatpickr-day[aria-label*='#{tomorrow.strftime('%B %-d, %Y')}']", wait: 3)
            expect(tomorrow_element).not_to have_css('.flatpickr-disabled')
          end
        end
      end
    end

    context '複合情況：週休息日 + 特殊休息日' do
      let(:special_closure_date) { Date.current.next_occurring(:wednesday) }
      
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

        # 等待日曆載入
        expect(page).to have_css('.flatpickr-calendar', wait: 5)

        within '.flatpickr-calendar' do
          # 檢查週休息日被禁用
          next_monday = Date.current.next_occurring(:monday)
          monday_element = find(".flatpickr-day[aria-label*='#{next_monday.strftime('%B %-d, %Y')}']", wait: 3)
          expect(monday_element).to have_css('.flatpickr-disabled')

          # 檢查特殊休息日被禁用
          closure_element = find(".flatpickr-day[aria-label*='#{special_closure_date.strftime('%B %-d, %Y')}']", wait: 3)
          expect(closure_element).to have_css('.flatpickr-disabled')

          # 檢查其他營業日可選
          next_thursday = Date.current.next_occurring(:thursday)
          thursday_element = find(".flatpickr-day[aria-label*='#{next_thursday.strftime('%B %-d, %Y')}']", wait: 3)
          expect(thursday_element).not_to have_css('.flatpickr-disabled')
        end
      end
    end
  end

  describe '日期選擇功能' do
    it '應該能夠選擇營業日並更新表單欄位' do
      visit new_admin_restaurant_reservation_path(restaurant)

      # 等待日曆載入
      expect(page).to have_css('.flatpickr-calendar', wait: 5)

      # 選擇明天的日期（假設是營業日）
      tomorrow = Date.current + 1.day
      
      within '.flatpickr-calendar' do
        tomorrow_element = find(".flatpickr-day[aria-label*='#{tomorrow.strftime('%B %-d, %Y')}']", wait: 3)
        tomorrow_element.click unless tomorrow_element[:class].include?('flatpickr-disabled')
      end

      # 檢查隱藏欄位是否被更新
      expect(page).to have_field('reservation[reservation_datetime]', type: :hidden)
    end
  end

  describe 'API 呼叫處理' do
    context '當 available_days API 失敗' do
      before do
        # 模擬 API 失敗
        allow_any_instance_of(RestaurantsController).to receive(:available_days).and_raise(StandardError.new('API Error'))
      end

      it '應該使用備用日期選擇器' do
        visit new_admin_restaurant_reservation_path(restaurant)

        # 應該仍然有日曆可用（備用版本）
        expect(page).to have_css('.flatpickr-calendar', wait: 5)
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

      # 等待日曆載入
      expect(page).to have_css('.flatpickr-calendar', wait: 5)

      # 檢查週一被禁用
      next_monday = Date.current.next_occurring(:monday)
      within '.flatpickr-calendar' do
        monday_element = find(".flatpickr-day[aria-label*='#{next_monday.strftime('%B %-d, %Y')}']", wait: 3)
        expect(monday_element).to have_css('.flatpickr-disabled')
      end

      # 改變人數
      fill_in '總人數', with: '6'

      # 等待可能的重新載入
      sleep 0.5

      # 週一應該仍然被禁用
      within '.flatpickr-calendar' do
        monday_element = find(".flatpickr-day[aria-label*='#{next_monday.strftime('%B %-d, %Y')}']", wait: 3)
        expect(monday_element).to have_css('.flatpickr-disabled')
      end
    end
  end
end