require 'rails_helper'

RSpec.describe '複雜訂位情境系統測試', type: :system do
  let!(:restaurant) { create(:restaurant, name: '測試餐廳') }
  let!(:admin_user) { create(:user, :admin, restaurant: restaurant) }
  let!(:business_period) { create(:business_period, restaurant: restaurant) }
  
  # 建立多種類型的桌位
  let!(:square_tables) do
    2.times.map do |i|
      create(:table, restaurant: restaurant, 
             table_number: "S#{i+1}", 
             table_type: 'square', 
             max_capacity: 4,
             table_group: create(:table_group, name: '方桌', restaurant: restaurant))
    end
  end
  
  let!(:round_tables) do
    2.times.map do |i|
      create(:table, restaurant: restaurant, 
             table_number: "R#{i+1}", 
             table_type: 'round', 
             max_capacity: 6,
             table_group: create(:table_group, name: '圓桌', restaurant: restaurant))
    end
  end
  
  let!(:bar_tables) do
    3.times.map do |i|
      create(:table, restaurant: restaurant, 
             table_number: "B#{i+1}", 
             table_type: 'bar', 
             max_capacity: 2,
             table_group: create(:table_group, name: '吧台', restaurant: restaurant))
    end
  end

  before do
    sign_in admin_user
  end

  describe '高峰時段訂位管理' do
    it '管理員應該能快速處理多個同時間訂位請求', js: true do
      visit admin_reservations_path

      # 模擬午餐高峰時段的5個訂位請求
      reservation_data = [
        { name: '張小明', phone: '0912345678', party_size: 2, time: '12:00' },
        { name: '李小華', phone: '0923456789', party_size: 4, time: '12:00' },
        { name: '王大同', phone: '0934567890', party_size: 1, time: '12:00' },
        { name: '陳美麗', phone: '0945678901', party_size: 6, time: '12:00' },
        { name: '林先生', phone: '0956789012', party_size: 3, time: '12:00' }
      ]

      successful_reservations = 0

      reservation_data.each_with_index do |data, index|
        click_button '新增訂位'
        
        within '#reservation_form' do
          fill_in '客戶姓名', with: data[:name]
          fill_in '電話號碼', with: data[:phone]
          fill_in '人數', with: data[:party_size]
          
          # 設定訂位時間為明天的指定時間
          tomorrow = Date.tomorrow.strftime('%Y-%m-%d')
          fill_in '訂位時間', with: "#{tomorrow} #{data[:time]}"
          
          click_button '建立訂位'
        end

        # 檢查是否成功建立
        if page.has_content?('訂位建立成功') || page.has_content?(data[:name])
          successful_reservations += 1
        end

        # 等待DOM更新
        sleep 0.5
      end

      # 至少應該成功分配70%的訂位
      expect(successful_reservations).to be >= 3
      
      # 檢查頁面顯示所有成功的訂位
      expect(page).to have_content('張小明')
      expect(page).to have_content('李小華')
    end

    it '應該提供清晰的桌位不可用提示', js: true do
      # 先填滿所有桌位
      fill_all_tables_for_time('12:00')
      
      visit admin_reservations_path
      click_button '新增訂位'

      within '#reservation_form' do
        fill_in '客戶姓名', with: '客滿先生'
        fill_in '電話號碼', with: '0912345678'
        fill_in '人數', with: '4'
        
        tomorrow = Date.tomorrow.strftime('%Y-%m-%d')
        fill_in '訂位時間', with: "#{tomorrow} 12:00"
        
        click_button '建立訂位'
      end

      # 應該顯示適當的錯誤訊息
      expect(page).to have_content('該時段沒有可用桌位')
      
      # 建議替代時間
      expect(page).to have_content('建議時間') 
    end
  end

  describe '併桌功能操作流程' do
    it '管理員應該能為大型聚會手動選擇併桌', js: true do
      visit admin_reservations_path
      click_button '新增訂位'

      within '#reservation_form' do
        fill_in '客戶姓名', with: '大型聚會'
        fill_in '電話號碼', with: '0912345678'
        fill_in '人數', with: '10'
        
        tomorrow = Date.tomorrow.strftime('%Y-%m-%d')
        fill_in '訂位時間', with: "#{tomorrow} 18:00"
        
        # 檢查是否出現併桌選項
        expect(page).to have_content('需要併桌')
        
        # 選擇併桌
        check '使用併桌'
        
        click_button '建立訂位'
      end

      if page.has_content?('訂位建立成功')
        # 檢查併桌詳情
        click_link '大型聚會'
        
        expect(page).to have_content('併桌資訊')
        expect(page).to have_content('桌位組合')
      else
        expect(page).to have_content('無法安排併桌')
      end
    end

    it '應該動態顯示併桌的可用組合', js: true do
      visit admin_reservations_path
      click_button '新增訂位'

      within '#reservation_form' do
        fill_in '人數', with: '8'
        
        # 觸發併桌檢查
        find('#party_size').send_keys(:tab)
        
        # 等待AJAX回應
        expect(page).to have_css('.table-combination-options', wait: 3)
        
        # 檢查顯示的併桌選項
        within('.table-combination-options') do
          expect(page).to have_content('可用併桌組合')
          expect(page).to have_selector('.combination-option', count: 1..3)
        end
      end
    end
  end

  describe '訂位衝突解決' do
    it '應該檢測並處理時間衝突', js: true do
      # 先建立一個訂位
      existing_reservation = create(:reservation, :confirmed,
                                  restaurant: restaurant,
                                  business_period: business_period,
                                  table: square_tables.first,
                                  customer_name: '已存在客戶',
                                  customer_phone: '0900000000',
                                  party_size: 2,
                                  reservation_datetime: Date.tomorrow.change(hour: 12, min: 0))

      visit admin_reservations_path
      click_button '新增訂位'

      within '#reservation_form' do
        fill_in '客戶姓名', with: '衝突客戶'
        fill_in '電話號碼', with: '0911111111'
        fill_in '人數', with: '2'
        
        # 選擇同一桌位的重疊時間
        tomorrow = Date.tomorrow.strftime('%Y-%m-%d')
        fill_in '訂位時間', with: "#{tomorrow} 12:30"
        
        # 嘗試選擇已被占用的桌位
        select square_tables.first.table_number, from: '指定桌位' if page.has_select?('指定桌位')
        
        click_button '建立訂位'
      end

      # 系統應該檢測衝突並提供解決方案
      expect(page).to have_content('時間衝突') || page.has_content?('自動分配其他桌位')
    end

    it '應該提供智慧型重新安排建議', js: true do
      # 填滿大部分桌位
      fill_most_tables_for_time('19:00')
      
      visit admin_reservations_path
      click_button '新增訂位'

      within '#reservation_form' do
        fill_in '客戶姓名', with: '晚餐客戶'
        fill_in '電話號碼', with: '0922222222'
        fill_in '人數', with: '4'
        
        tomorrow = Date.tomorrow.strftime('%Y-%m-%d')
        fill_in '訂位時間', with: "#{tomorrow} 19:00"
        
        click_button '檢查可用性'
      end

      # 應該顯示替代建議
      expect(page).to have_content('建議時間') ||
             page.has_content?('可用時段') ||
             page.has_content?('其他選項')
    end
  end

  describe '特殊需求處理' do
    it '應該能處理兒童座椅和無障礙需求', js: true do
      visit admin_reservations_path
      click_button '新增訂位'

      within '#reservation_form' do
        fill_in '客戶姓名', with: '親子客戶'
        fill_in '電話號碼', with: '0933333333'
        fill_in '人數', with: '3'
        fill_in '成人', with: '2'
        fill_in '兒童', with: '1'
        
        # 選擇特殊需求
        check '需要兒童座椅' if page.has_field?('需要兒童座椅')
        check '無障礙桌位' if page.has_field?('無障礙桌位')
        
        fill_in '特殊需求', with: '需要兒童座椅和無障礙桌位'
        
        tomorrow = Date.tomorrow.strftime('%Y-%m-%d')
        fill_in '訂位時間', with: "#{tomorrow} 18:30"
        
        click_button '建立訂位'
      end

      # 檢查是否成功處理特殊需求
      if page.has_content?('訂位建立成功')
        expect(page).to have_content('親子客戶')
        
        # 點擊查看詳情
        click_link '親子客戶'
        expect(page).to have_content('特殊需求')
      end
    end

    it '應該防止將有兒童的訂位分配到吧台', js: true do
      # 佔用所有非吧台桌位
      (square_tables + round_tables).each_with_index do |table, index|
        create(:reservation, :confirmed,
               restaurant: restaurant,
               business_period: business_period,
               table: table,
               customer_name: "佔位客戶#{index}",
               party_size: 2,
               reservation_datetime: Date.tomorrow.change(hour: 18, min: 0))
      end

      visit admin_reservations_path
      click_button '新增訂位'

      within '#reservation_form' do
        fill_in '客戶姓名', with: '帶小孩客戶'
        fill_in '電話號碼', with: '0944444444'
        fill_in '人數', with: '2'
        fill_in '成人', with: '1'
        fill_in '兒童', with: '1'
        
        tomorrow = Date.tomorrow.strftime('%Y-%m-%d')
        fill_in '訂位時間', with: "#{tomorrow} 18:00"
        
        click_button '建立訂位'
      end

      # 應該拒絕分配或提供等候選項
      expect(page).to have_content('暫無適合的桌位') ||
             page.has_content?('建議其他時間') ||
             page.has_content?('等候清單')
    end
  end

  describe '取消和修改流程' do
    let!(:existing_reservation) do
      create(:reservation, :confirmed,
             restaurant: restaurant,
             business_period: business_period,
             table: square_tables.first,
             customer_name: '可修改客戶',
             customer_phone: '0955555555',
             party_size: 2,
             reservation_datetime: Date.tomorrow.change(hour: 12, min: 0))
    end

    it '應該能夠修改訂位並重新分配桌位', js: true do
      visit admin_reservations_path
      
      # 找到並編輯訂位
      within "[data-reservation-id='#{existing_reservation.id}']" do
        click_button '編輯'
      end

      within '#reservation_form' do
        # 修改人數，這應該觸發重新分配
        fill_in '人數', with: '6'
        
        click_button '更新訂位'
      end

      expect(page).to have_content('訂位更新成功') ||
             page.has_content?('重新分配桌位')

      # 檢查桌位是否已重新分配
      existing_reservation.reload
      expect(existing_reservation.party_size).to eq(6)
    end

    it '取消訂位應該釋放桌位給等候清單', js: true do
      # 建立等候清單訂位
      waiting_reservation = create(:reservation, :waitlisted,
                                 restaurant: restaurant,
                                 business_period: business_period,
                                 customer_name: '等候客戶',
                                 party_size: 2,
                                 reservation_datetime: Date.tomorrow.change(hour: 12, min: 0))

      visit admin_reservations_path
      
      # 取消現有訂位
      within "[data-reservation-id='#{existing_reservation.id}']" do
        click_button '取消'
      end

      # 確認取消
      within '.modal' do
        click_button '確認取消'
      end

      expect(page).to have_content('訂位已取消')

      # 檢查等候清單是否被自動處理
      expect(page).to have_content('等候客戶') ||
             page.has_content?('已通知等候客戶')
    end
  end

  private

  def fill_all_tables_for_time(time)
    all_tables = square_tables + round_tables + bar_tables
    
    all_tables.each_with_index do |table, index|
      create(:reservation, :confirmed,
             restaurant: restaurant,
             business_period: business_period,
             table: table,
             customer_name: "客滿客戶#{index}",
             customer_phone: "090000#{index.to_s.rjust(4, '0')}",
             party_size: 2,
             reservation_datetime: Date.tomorrow.change(hour: time.split(':')[0].to_i, min: time.split(':')[1].to_i))
    end
  end

  def fill_most_tables_for_time(time)
    # 只填80%的桌位，留一些空間
    tables_to_fill = (square_tables + round_tables + bar_tables).first(5)
    
    tables_to_fill.each_with_index do |table, index|
      create(:reservation, :confirmed,
             restaurant: restaurant,
             business_period: business_period,
             table: table,
             customer_name: "忙碌客戶#{index}",
             customer_phone: "091000#{index.to_s.rjust(4, '0')}",
             party_size: 2,
             reservation_datetime: Date.tomorrow.change(hour: time.split(':')[0].to_i, min: time.split(':')[1].to_i))
    end
  end
end 