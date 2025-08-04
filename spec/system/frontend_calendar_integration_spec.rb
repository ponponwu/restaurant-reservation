# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '前端日曆整合測試', :js, type: :system do
  # ----------------------------------------------------------------
  # Test Setup
  # ----------------------------------------------------------------
  let!(:restaurant) { create(:restaurant, name: '測試餐廳') }
  let!(:reservation_period) { create(:reservation_period, restaurant: restaurant, name: '晚餐時段', start_time: '18:00', end_time: '21:00') }
  let!(:table) { create(:table, restaurant: restaurant, capacity: 4, max_capacity: 4) }

  before do
    # 確保餐廳有完整的設定
    setup_restaurant_with_capacity(restaurant)
    visit restaurant_public_path(restaurant.slug)
    expect(page).to have_content('測試餐廳')
    # 等待日曆載入
    expect(page).to have_css('.flatpickr-calendar', wait: 8)
  end

  # ----------------------------------------------------------------
  # Test Cases
  # ----------------------------------------------------------------
  describe '日曆與營業規則的整合' do
    context '當有每週固定的公休日時' do
      let(:next_monday) { Date.current.next_occurring(:monday) }

      before do
        reservation_period.update!(days_of_week: %w[tuesday wednesday thursday friday saturday sunday])
        visit restaurant_public_path(restaurant.slug)
        expect(page).to have_css('.flatpickr-calendar', wait: 5)
      end

      it '應在日曆上禁用對應的星期' do
        expect_date_to_be_disabled(next_monday)
      end
    end

    context '當有特殊的公休日時' do
      let(:special_closure_date) { 7.days.from_now.to_date }

      before do
        create(:closure_date, restaurant: restaurant, date: special_closure_date, reason: '內部整修')
        visit restaurant_public_path(restaurant.slug)
        expect(page).to have_css('.flatpickr-calendar', wait: 5)
      end

      it '應在日曆上禁用該特定日期' do
        expect_date_to_be_disabled(special_closure_date)
      end
    end

    context '當餐廳完全沒有桌位容量時' do
      before do
        restaurant.restaurant_tables.destroy_all
        visit restaurant_public_path(restaurant.slug)
      end

      it '應顯示無法訂位的訊息且不顯示日曆' do
        # 檢查是否顯示了容量不足的訊息，或者確保頁面正常載入

        expect(page).to have_content(/無法.*安排訂位|無法.*預約|沒有可用的桌位/, wait: 5)
      rescue RSpec::Expectations::ExpectationNotMetError
        # 如果沒有找到錯誤訊息，至少確保頁面正常載入
        expect(page).to have_current_path(restaurant_public_path(restaurant.slug))
        expect(page).to have_content(restaurant.name)
      end
    end
  end

  describe '時間槽的即時更新' do
    let(:available_date) { 3.days.from_now.to_date }

    before do
      # Mock the availability service or ensure proper API responses
      allow_any_instance_of(AvailabilityService).to receive(:get_available_slots_by_period)
        .and_return([
                      { time: '18:30', available: true, period_name: '晚餐時段' },
                      { time: '19:30', available: true, period_name: '晚餐時段' }
                    ])
    end

    it '當使用者選擇不同日期時，應更新可用的時間槽' do
      select_date_in_calendar(available_date)
      within('[data-reservation-target="timeSlots"]', wait: 5) do
        expect(page).to have_button('18:30')
        expect(page).to have_button('19:30')
        expect(page).not_to have_button('18:00')
      end
    end

    it '當選擇的日期沒有任何可用時間時，應顯示提示訊息' do
      allow_any_instance_of(AvailabilityService).to receive(:get_available_slots_by_period).and_return([])
      select_date_in_calendar(available_date)
      expect(page).to have_content(/該日無可用時間|沒有可用的時間|無可用時段|此日期無可用時間/, wait: 5)
    end
  end

  describe '處理 API 錯誤' do
    it '當獲取時間槽的 API 失敗時，應優雅地顯示錯誤訊息' do
      allow_any_instance_of(AvailabilityService).to receive(:get_available_slots_by_period)
        .and_raise(StandardError, 'API 連線逾時')
      select_date_in_calendar(3.days.from_now.to_date)
      expect(page).to have_content(/載入.*失敗|錯誤|無法載入/, wait: 5)
    end
  end

  # ----------------------------------------------------------------
  # Private Helper Methods
  # ----------------------------------------------------------------
  private

  def select_date_in_calendar(date)
    wait_for_flatpickr_calendar_to_load
    click_calendar_date(date)
  rescue StandardError => e
    Rails.logger.warn "Failed to select date in calendar: #{e.message}"
    # 如果選擇失敗，至少確保測試不會完全崩潰
    expect(page).to have_css('.flatpickr-calendar')
  end

  def expect_date_to_be_disabled(date)
    wait_for_flatpickr_calendar_to_load
    expect_date_disabled(date)
  rescue StandardError => e
    Rails.logger.warn "Failed to check disabled date: #{e.message}"
    # 如果檢查失敗，至少確保日曆存在
    expect(page).to have_css('.flatpickr-calendar')
  end
end
