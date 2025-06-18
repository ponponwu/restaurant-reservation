require 'rails_helper'

RSpec.describe '訂位流程', type: :system, js: true do
  let(:restaurant) { create(:restaurant, name: '測試餐廳') }
  let(:business_period) { create(:business_period, restaurant: restaurant, name: '晚餐時段') }
  let(:table) { create(:table, restaurant: restaurant, table_number: 'A1') }

  before do
    # 設定餐廳的基本資料
    business_period
    table
    
    # Mock 桌位分配服務
    allow_any_instance_of(ReservationAllocatorService).to receive(:allocate_table).and_return(table)
    allow_any_instance_of(ReservationAllocatorService).to receive(:check_availability).and_return({ has_availability: true })
  end

  scenario '用戶完成完整的訂位流程' do
    # 1. 訪問餐廳頁面
    visit restaurant_public_path(restaurant)
    
    expect(page).to have_content('測試餐廳')
    expect(page).to have_content('請選擇您的預約資訊')

    # 2. 選擇人數
    select '2 人', from: 'reservation[adult_count]'
    select '1 人', from: 'reservation[child_count]'

    # 3. 選擇日期
    # 點擊日期輸入框
    find('input[data-reservation-target="date"]').click
    
    # 等待 flatpickr 加載
    sleep 1
    
    # 選擇今天的日期（假設可用）
    within('.flatpickr-calendar') do
      find('.flatpickr-day.today').click
    end

    # 4. 等待時間槽加載
    expect(page).to have_content('晚餐時段', wait: 5)

    # 5. 選擇時間
    # 假設會有時間選項出現
    first('.time-option').click

    # 6. 點擊進行預約
    click_button '進行預約'

    # 7. 填寫訂位表單
    expect(page).to have_content('預約 測試餐廳')
    
    fill_in '聯絡人姓名', with: '王小明'
    fill_in '聯絡電話', with: '0912345678'
    fill_in '電子郵件', with: 'wang@example.com'
    fill_in '特殊需求', with: '希望靠窗的座位'

    # 8. 提交訂位
    click_button '送出預約申請'

    # 9. 確認成功訊息
    expect(page).to have_content('訂位申請已送出')
    expect(current_path).to eq(restaurant_public_path(restaurant))

    # 10. 確認資料庫中的訂位記錄
    reservation = Reservation.last
    expect(reservation.restaurant).to eq(restaurant)
    expect(reservation.customer_name).to eq('王小明')
    expect(reservation.customer_phone).to eq('0912345678')
    expect(reservation.customer_email).to eq('wang@example.com')
    expect(reservation.party_size).to eq(3) # 2 大人 + 1 小孩
    expect(reservation.special_requests).to eq('希望靠窗的座位')
    expect(reservation.status).to eq('pending')
  end

  scenario '當沒有可用時間時顯示適當訊息' do
    # Mock 沒有可用時間槽
    allow_any_instance_of(Restaurant).to receive(:available_time_options_for_date).and_return([])
    
    visit restaurant_public_path(restaurant)
    
    # 選擇人數
    select '2 人', from: 'reservation[adult_count]'
    
    # 選擇日期
    find('input[data-reservation-target="date"]').click
    sleep 1
    
    within('.flatpickr-calendar') do
      find('.flatpickr-day.today').click
    end

    # 應該顯示無可用時間的訊息
    expect(page).to have_content('該日無可用時間', wait: 5)
  end

  scenario '驗證表單錯誤處理' do
    # 跳過前面步驟，直接到訂位表單
    visit new_restaurant_reservation_path(restaurant, {
      date: Date.current.strftime('%Y-%m-%d'),
      adults: 2,
      children: 0,
      time: '18:00',
      period_id: business_period.id
    })

    # 提交空白表單
    click_button '送出預約申請'

    # 應該顯示驗證錯誤
    expect(page).to have_content('can\'t be blank')
  end

  scenario '處理餐廳公休日' do
    # Mock 餐廳公休
    allow_any_instance_of(Restaurant).to receive(:closed_on_date?).and_return(true)
    
    visit restaurant_public_path(restaurant)
    
    # 選擇人數
    select '2 人', from: 'reservation[adult_count]'
    
    # 選擇日期
    find('input[data-reservation-target="date"]').click
    sleep 1
    
    within('.flatpickr-calendar') do
      find('.flatpickr-day.today').click
    end

    # 應該顯示公休訊息
    expect(page).to have_content('餐廳當天公休', wait: 5)
  end

  scenario '處理桌位已滿的情況' do
    # Mock 沒有可用桌位
    allow_any_instance_of(ReservationAllocatorService).to receive(:allocate_table).and_return(nil)
    
    # 跳到訂位表單
    visit new_restaurant_reservation_path(restaurant, {
      date: Date.current.strftime('%Y-%m-%d'),
      adults: 2,
      children: 0,
      time_slot: '18:00',
      business_period_id: business_period.id
    })

    fill_in '聯絡人姓名', with: '王小明'
    fill_in '聯絡電話', with: '0912345678'

    click_button '送出預約申請'

    # 應該顯示桌位已滿的錯誤訊息
    expect(page).to have_content('該時段已無可用桌位')
  end

  describe 'Dynamic party size adjustment', js: true do
    it 'dynamically adjusts child options when adult count changes' do
      visit restaurant_public_path(restaurant.slug)
      
      # 等待頁面載入完成
      expect(page).to have_selector('[data-reservation-target="adultCount"]')
      
      # 檢查初始狀態：大人選2，小孩可選0-4
      adult_select = find('[data-reservation-target="adultCount"]')
      child_select = find('[data-reservation-target="childCount"]')
      
      expect(adult_select.value).to eq('2')
      child_options = child_select.all('option').map(&:value)
      expect(child_options).to eq(['0', '1', '2', '3', '4'])
      
      # 將大人數改為4，小孩選項應該變為0-2
      adult_select.select('4')
      
      # 等待JavaScript處理
      sleep 1
      
      child_options = child_select.all('option').map(&:value)
      expect(child_options).to eq(['0', '1', '2'])
      
      # 將大人數改為6（最大值），小孩選項應該只有0
      adult_select.select('6')
      
      # 等待JavaScript處理
      sleep 1
      
      child_options = child_select.all('option').map(&:value)
      expect(child_options).to eq(['0'])
    end
    
    it 'prevents total party size from exceeding maximum' do
      visit restaurant_public_path(restaurant.slug)
      
      # 等待頁面載入完成
      expect(page).to have_selector('[data-reservation-target="adultCount"]')
      
      adult_select = find('[data-reservation-target="adultCount"]')
      child_select = find('[data-reservation-target="childCount"]')
      
      # 選擇3個大人，3個小孩
      adult_select.select('3')
      sleep 0.5
      child_select.select('3')
      sleep 1
      
      # 總人數應該是6，符合上限
      expect(adult_select.value).to eq('3')
      expect(child_select.value).to eq('3')
      
      # 嘗試增加大人數到5，小孩數應該自動調整為1
      adult_select.select('5')
      sleep 1
      
      expect(child_select.value).to eq('1')
    end
  end
end 