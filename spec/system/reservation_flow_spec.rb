# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '訂位流程', :js, type: :system do
  let!(:restaurant) { create(:restaurant, name: '測試餐廳') }
  let!(:reservation_period) { create(:reservation_period, restaurant: restaurant) }
  let!(:table) { create(:table, restaurant: restaurant, capacity: 10, max_capacity: 10) }

  before do
    visit restaurant_public_path(restaurant.slug)
    expect(page).to have_content('測試餐廳')
  end

  it '用戶可以成功完成訂位' do
    select '2', from: 'reservation[adult_count]'

    # 根據實際的 HTML 結構，點擊日曆中的日期
    find('.flatpickr-next-month').click
    first('.flatpickr-day', text: '10').click

    within('[data-reservation-target="timeSlots"]', wait: 5) do
      first('button').click
    end

    click_button '下一步'

    fill_in '聯絡人姓名', with: '王小明'
    fill_in '聯絡電話', with: '0912345678'
    click_button '送出預約申請'

    expect(page).to have_content('訂位建立成功', wait: 5)
  end
end
