# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '桌位分配系統', :js, type: :system do
  let!(:restaurant) { create(:restaurant, name: '測試餐廳') }
  let!(:admin_user) { create(:user, :super_admin, restaurant: restaurant) }
  let!(:reservation_period) { create(:reservation_period, restaurant: restaurant) }

  before do
    sign_in admin_user
    create_list(:table, 5, restaurant: restaurant)
    visit new_admin_restaurant_reservation_path(restaurant)
    expect(page).to have_content('建立訂位')
  end

  it '管理員可以成功建立一個訂位' do
    fill_in '客戶姓名', with: '張小明'
    fill_in '電話號碼', with: '0912345678'
    fill_in '總人數', with: '2'

    # 選擇日期和時間
    date = 1.day.from_now
    time = '12:00'

    find('.flatpickr-next-month').click
    first('.flatpickr-day', text: date.day.to_s).click
    select reservation_period.name, from: 'reservation[reservation_period_id]'
    fill_in 'reservation[reservation_time]', with: time
    select first('#reservation_table_id option:not([value=""])').text, from: 'reservation_table_id'

    # 手動設定隱藏的 datetime 欄位
    datetime_string = "#{date.strftime('%Y-%m-%d')} #{time}"
    page.execute_script("document.getElementById('reservation_reservation_datetime').value = '#{datetime_string}'")

    click_button '建立訂位'

    expect(page).to have_content('訂位建立成功', wait: 5)
  end
end
