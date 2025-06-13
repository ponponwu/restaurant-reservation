require 'rails_helper'

RSpec.describe 'Admin Reservation Policies', type: :system, js: true do
  let(:admin) { create(:user, :admin) }
  let(:restaurant) { create(:restaurant) }
  let(:reservation_policy) { restaurant.reservation_policy || restaurant.create_reservation_policy! }

  before do
    sign_in admin
    visit admin_restaurant_settings_restaurant_reservation_policies_path(restaurant)
  end

  describe 'Reservation Toggle Switch' do
    context 'when reservation is enabled' do
      before do
        reservation_policy.update!(reservation_enabled: true)
        visit admin_restaurant_settings_restaurant_reservation_policies_path(restaurant)
      end

      it 'displays enabled state correctly' do
        within('[data-controller="reservation-policy"]') do
          expect(page).to have_content('已啟用')
          expect(page).to have_css('[data-reservation-policy-target="toggle"].bg-blue-600')
          expect(page).to have_css('[data-reservation-policy-target="toggleButton"].translate-x-5')
          
          # Settings should be enabled
          expect(page).not_to have_css('[data-reservation-policy-target="settings"].opacity-50')
        end
      end

      it 'disables reservation when clicked' do
        within('[data-controller="reservation-policy"]') do
          # 點擊切換開關
          find('[data-reservation-policy-target="toggle"]').click
          
          # 等待頁面更新
          expect(page).to have_content('已停用')
          expect(page).to have_css('[data-reservation-policy-target="toggle"].bg-gray-200')
          expect(page).to have_css('[data-reservation-policy-target="toggleButton"].translate-x-0')
          
          # Settings should be disabled
          expect(page).to have_css('[data-reservation-policy-target="settings"].opacity-50')
        end

        # 驗證資料庫已更新
        reservation_policy.reload
        expect(reservation_policy.reservation_enabled).to be false
      end
    end

    context 'when reservation is disabled' do
      before do
        reservation_policy.update!(reservation_enabled: false)
        visit admin_restaurant_settings_restaurant_reservation_policies_path(restaurant)
      end

      it 'displays disabled state correctly' do
        within('[data-controller="reservation-policy"]') do
          expect(page).to have_content('已停用')
          expect(page).to have_css('[data-reservation-policy-target="toggle"].bg-gray-200')
          expect(page).to have_css('[data-reservation-policy-target="toggleButton"].translate-x-0')
          
          # Settings should be disabled
          expect(page).to have_css('[data-reservation-policy-target="settings"].opacity-50')
        end
      end

      it 'enables reservation when clicked' do
        within('[data-controller="reservation-policy"]') do
          # 點擊切換開關
          find('[data-reservation-policy-target="toggle"]').click
          
          # 等待頁面更新
          expect(page).to have_content('已啟用')
          expect(page).to have_css('[data-reservation-policy-target="toggle"].bg-blue-600')
          expect(page).to have_css('[data-reservation-policy-target="toggleButton"].translate-x-5')
          
          # Settings should be enabled
          expect(page).not_to have_css('[data-reservation-policy-target="settings"].opacity-50')
        end

        # 驗證資料庫已更新
        reservation_policy.reload
        expect(reservation_policy.reservation_enabled).to be true
      end

      it 'shows warning message when disabled' do
        expect(page).to have_css('.bg-red-50')
        expect(page).to have_content('線上訂位功能目前已停用')
        expect(page).to have_content('客戶將無法透過網站進行訂位')
      end
    end
  end

  describe 'Deposit Settings Toggle' do
    context 'when deposit is disabled' do
      before do
        reservation_policy.update!(deposit_required: false)
        visit admin_restaurant_settings_restaurant_reservation_policies_path(restaurant)
      end

      it 'hides deposit fields initially' do
        expect(page).to have_css('[data-reservation-policy-target="depositFields"].hidden')
      end

      it 'shows deposit fields when enabled' do
        # 啟用押金設定
        check 'reservation_policy_deposit_required'
        
        # 押金設定欄位應該顯示
        expect(page).not_to have_css('[data-reservation-policy-target="depositFields"].hidden')
        expect(page).to have_field('reservation_policy_deposit_amount')
        expect(page).to have_select('reservation_policy_deposit_per_person')
      end
    end

    context 'when deposit is enabled' do
      before do
        reservation_policy.update!(
          deposit_required: true,
          deposit_amount: 200,
          deposit_per_person: false
        )
        visit admin_restaurant_settings_restaurant_reservation_policies_path(restaurant)
      end

      it 'shows deposit fields initially' do
        expect(page).not_to have_css('[data-reservation-policy-target="depositFields"].hidden')
        expect(page).to have_field('reservation_policy_deposit_amount', with: '200')
      end

      it 'hides deposit fields when disabled' do
        # 停用押金設定
        uncheck 'reservation_policy_deposit_required'
        
        # 押金設定欄位應該隱藏
        expect(page).to have_css('[data-reservation-policy-target="depositFields"].hidden')
      end
    end
  end

  describe 'Form Submission' do
    it 'updates basic settings successfully' do
      fill_in 'reservation_policy_advance_booking_days', with: '14'
      fill_in 'reservation_policy_minimum_advance_hours', with: '4'
      fill_in 'reservation_policy_max_party_size', with: '8'
      fill_in 'reservation_policy_min_party_size', with: '2'
      
      click_button '儲存設定'
      
      expect(page).to have_content('訂位政策已更新')
      
      reservation_policy.reload
      expect(reservation_policy.advance_booking_days).to eq(14)
      expect(reservation_policy.minimum_advance_hours).to eq(4)
      expect(reservation_policy.max_party_size).to eq(8)
      expect(reservation_policy.min_party_size).to eq(2)
    end

    it 'updates phone limit settings successfully' do
      fill_in 'reservation_policy_max_bookings_per_phone', with: '2'
      fill_in 'reservation_policy_phone_limit_period_days', with: '7'
      
      click_button '儲存設定'
      
      expect(page).to have_content('訂位政策已更新')
      
      reservation_policy.reload
      expect(reservation_policy.max_bookings_per_phone).to eq(2)
      expect(reservation_policy.phone_limit_period_days).to eq(7)
    end

    it 'updates deposit settings successfully' do
      check 'reservation_policy_deposit_required'
      fill_in 'reservation_policy_deposit_amount', with: '300'
      select '按人數計算', from: 'reservation_policy_deposit_per_person'
      
      click_button '儲存設定'
      
      expect(page).to have_content('訂位政策已更新')
      
      reservation_policy.reload
      expect(reservation_policy.deposit_required).to be true
      expect(reservation_policy.deposit_amount).to eq(300)
      expect(reservation_policy.deposit_per_person).to be true
    end

    it 'updates policy text fields successfully' do
      fill_in 'reservation_policy_no_show_policy', with: '未到場將記錄黑名單'
      fill_in 'reservation_policy_modification_policy', with: '24小時前可免費修改'
      fill_in 'reservation_policy_special_rules', with: '大型聚餐需提前3天預約'
      
      click_button '儲存設定'
      
      expect(page).to have_content('訂位政策已更新')
      
      reservation_policy.reload
      expect(reservation_policy.no_show_policy).to eq('未到場將記錄黑名單')
      expect(reservation_policy.modification_policy).to eq('24小時前可免費修改')
      expect(reservation_policy.special_rules).to eq('大型聚餐需提前3天預約')
    end

    context 'with validation errors' do
      it 'shows error messages for invalid data' do
        fill_in 'reservation_policy_min_party_size', with: '10'
        fill_in 'reservation_policy_max_party_size', with: '5'
        
        click_button '儲存設定'
        
        expect(page).to have_content('最小人數不能大於最大人數')
        expect(page).to have_css('.alert', text: /錯誤/)
      end

      it 'preserves form values after validation error' do
        fill_in 'reservation_policy_advance_booking_days', with: '21'
        fill_in 'reservation_policy_min_party_size', with: '10'
        fill_in 'reservation_policy_max_party_size', with: '5'
        
        click_button '儲存設定'
        
        # 錯誤後，正確的值應該保留
        expect(page).to have_field('reservation_policy_advance_booking_days', with: '21')
        expect(page).to have_field('reservation_policy_min_party_size', with: '10')
        expect(page).to have_field('reservation_policy_max_party_size', with: '5')
      end
    end
  end

  describe 'Phone Limit Information' do
    it 'displays phone limit explanation' do
      expect(page).to have_content('手機號碼訂位次數限制')
      expect(page).to have_content('同一手機號碼在30天內最多只能建立5個有效訂位')
      expect(page).to have_content('已取消或未到場的訂位不會計入限制')
    end
  end

  describe 'Deposit Type Selection' do
    before do
      reservation_policy.update!(deposit_required: true)
      visit admin_restaurant_settings_restaurant_reservation_policies_path(restaurant)
    end

    it 'provides deposit type options' do
      within('[data-reservation-policy-target="depositFields"]') do
        expect(page).to have_select('reservation_policy_deposit_per_person', 
                                   options: ['請選擇押金類型', '固定金額', '按人數計算'])
      end
    end
  end

  describe 'Navigation and Layout' do
    it 'shows correct page title and navigation' do
      expect(page).to have_content('訂位政策設定')
      expect(page).to have_link('取消')
      expect(page).to have_button('儲存設定')
    end

    it 'has proper form structure' do
      expect(page).to have_css('form#reservation_policy_form')
      expect(page).to have_css('[data-controller="reservation-policy"]')
    end
  end

  describe 'Real-time UI Updates' do
    it 'updates UI immediately when toggle is clicked' do
      # 確保開始時是啟用狀態
      reservation_policy.update!(reservation_enabled: true)
      visit admin_restaurant_settings_restaurant_reservation_policies_path(restaurant)
      
      expect(page).to have_content('已啟用')
      
      # 點擊切換
      find('[data-reservation-policy-target="toggle"]').click
      
      # UI 應該立即更新，不需要等待伺服器回應
      expect(page).to have_content('已停用')
      
      # 再次點擊切換
      find('[data-reservation-policy-target="toggle"]').click
      
      # 應該回到啟用狀態
      expect(page).to have_content('已啟用')
    end
  end

  describe 'Browser Compatibility' do
    it 'works without JavaScript (graceful degradation)', js: false do
      visit admin_restaurant_settings_restaurant_reservation_policies_path(restaurant)
      
      # 表單應該仍然可以提交
      fill_in 'reservation_policy_advance_booking_days', with: '20'
      click_button '儲存設定'
      
      expect(page).to have_content('訂位政策已更新')
      
      reservation_policy.reload
      expect(reservation_policy.advance_booking_days).to eq(20)
    end
  end
end 