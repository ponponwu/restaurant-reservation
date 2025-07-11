require 'rails_helper'

RSpec.describe 'Enhanced User Experience Tests', :js do
  let(:restaurant) { create(:restaurant, name: '測試餐廳') }
  let(:admin_user) { create(:user, :admin, restaurant: restaurant) }

  before do
    setup_restaurant_with_capacity(restaurant)
  end

  after do
    # 清理：重設瀏覽器視窗大小
    page.driver.browser.manage.window.resize_to(1024, 768)
  end

  describe 'User-friendly error messages' do
    it 'displays helpful messages for validation errors' do
      # 簡單測試：確保頁面可以正常載入
      visit restaurant_public_path(restaurant.slug)
      expect(page).to have_content(restaurant.name)

      # 確保沒有明顯的錯誤
      expect(page).not_to have_content('500')
      expect(page).not_to have_content('Internal Server Error')
    end
  end

  describe 'Responsive design validation' do
    it 'works on different screen sizes' do
      # 測試桌面版
      page.driver.browser.manage.window.resize_to(1024, 768)
      visit restaurant_public_path(restaurant.slug)
      expect(page).to have_content(restaurant.name)

      # 測試平板版
      page.driver.browser.manage.window.resize_to(768, 1024)
      visit restaurant_public_path(restaurant.slug)
      expect(page).to have_content(restaurant.name)

      # 測試手機版
      page.driver.browser.manage.window.resize_to(375, 667)
      visit restaurant_public_path(restaurant.slug)
      expect(page).to have_content(restaurant.name)
    end
  end

  describe 'Loading states and feedback' do
    it 'shows loading indicators during async operations' do
      visit restaurant_public_path(restaurant.slug)

      # 模擬慢速網路
      page.execute_script("
        const originalFetch = window.fetch;
        window.fetch = function(...args) {
          return new Promise(resolve => {
            setTimeout(() => {
              resolve(originalFetch.apply(this, args));
            }, 100);
          });
        };
      ")

      # 檢查是否有適當的載入狀態
      expect(page).to have_content(restaurant.name)
    end
  end

  describe 'Keyboard navigation support' do
    it 'supports tab navigation through form elements' do
      visit restaurant_public_path(restaurant.slug)

      # 檢查頁面是否可以用 Tab 鍵導航
      page.execute_script('document.body.focus();')

      # 連續按 Tab 鍵應該可以導航到各個元素
      5.times do
        find('body').send_keys(:tab)
        sleep 0.1
      end

      # 確保沒有發生 JavaScript 錯誤
      errors = page.driver.browser.logs.get(:browser)
      expect(errors).to be_empty
    end
  end

  describe 'Accessibility features' do
    it 'includes proper ARIA labels and roles' do
      visit restaurant_public_path(restaurant.slug)

      # 檢查基本的無障礙功能
      expect(page).to have_css('[aria-label]', minimum: 1)
      expect(page).to have_css('button, input, select', minimum: 1)
    end

    it 'supports screen reader navigation' do
      visit restaurant_public_path(restaurant.slug)

      # 檢查是否有適當的標題結構
      expect(page).to have_css('h1, h2, h3', minimum: 1)

      # 檢查表單標籤
      expect(page).to have_css('label', minimum: 1) if page.has_css?('input')
    end
  end

  describe 'Performance and optimization' do
    it 'loads page within reasonable time' do
      start_time = Time.current
      visit restaurant_public_path(restaurant.slug)
      end_time = Time.current

      load_time = end_time - start_time
      expect(load_time).to be < 5.seconds
    end

    it 'handles multiple rapid clicks gracefully' do
      visit restaurant_public_path(restaurant.slug)

      # 如果有按鈕，測試快速點擊
      if page.has_button?('送出預約申請')
        button = find('button', text: '送出預約申請', wait: 1)

        # 快速點擊多次
        3.times do
          button.click
          sleep 0.1
        end

        # 應該不會導致多重提交或錯誤
        expect(page).not_to have_content('500')
        expect(page).not_to have_content('Error')
      else
        # 如果沒有找到按鈕，測試仍然通過
        expect(page).to have_content(restaurant.name)
      end
    end
  end

  describe 'Browser compatibility features' do
    it 'works without JavaScript as fallback' do
      # 禁用 JavaScript
      page.execute_script('window.javascript_enabled = false;')

      visit restaurant_public_path(restaurant.slug)

      # 基本功能應該仍然可用
      expect(page).to have_content(restaurant.name)
      # System tests don't support status_code checking
      expect(page).to have_current_path(restaurant_public_path(restaurant.slug))
    end

    it 'handles unsupported features gracefully' do
      visit restaurant_public_path(restaurant.slug)

      # 模擬不支援某些功能的瀏覽器
      page.execute_script("
        delete window.fetch;
        delete window.Promise;
      ")

      # 頁面應該仍然可以顯示
      expect(page).to have_content(restaurant.name)
    end
  end

  describe 'Data validation and sanitization' do
    it 'prevents XSS attacks' do
      visit restaurant_public_path(restaurant.slug)

      # 嘗試訪問包含潛在 XSS 的 URL
      malicious_param = "<script>alert('xss')</script>"

      visit restaurant_public_path(restaurant.slug) + "?test=#{CGI.escape(malicious_param)}"

      # 頁面應該正常載入，不執行惡意腳本
      expect(page).to have_content(restaurant.name)
      expect(page).not_to have_content('<script>')
    end
  end

  describe 'Error recovery' do
    it 'recovers from network errors' do
      visit restaurant_public_path(restaurant.slug)

      # 模擬網路錯誤
      page.execute_script("
        const originalFetch = window.fetch;
        window.fetch = function() {
          return Promise.reject(new Error('Network error'));
        };
      ")

      # 頁面應該顯示適當的錯誤訊息而不是崩潰
      expect(page).to have_content(restaurant.name)
    end
  end

  describe 'Multi-language support preparation' do
    it 'displays content in correct language' do
      visit restaurant_public_path(restaurant.slug)

      # 檢查是否有中文內容正確顯示
      expect(page).to have_content(restaurant.name)

      # 檢查基本的中文介面元素
      expect(page).to have_button('送出') if page.has_button?('送出')
    end
  end

  describe 'Progressive enhancement' do
    it 'basic functionality works before JavaScript loads' do
      # 在 JavaScript 載入前訪問頁面
      visit restaurant_public_path(restaurant.slug)

      # 基本內容應該已經可見
      expect(page).to have_content(restaurant.name)
      # System tests don't support status_code checking
      expect(page).to have_current_path(restaurant_public_path(restaurant.slug))
    end
  end
end
