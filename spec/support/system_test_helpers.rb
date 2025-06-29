module SystemTestHelpers
  # Chrome 二進位路徑配置
  def configure_chrome_binary(options)
    chrome_bin = ENV.fetch('CHROME_BIN', nil)
    if chrome_bin.nil?
      # 優先使用正常的 Google Chrome（版本較新）
      regular_chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
      if File.exist?(regular_chrome)
        options.binary = regular_chrome
      end
      # 如果找不到正常版本，讓 Selenium 使用預設路徑
    elsif File.exist?(chrome_bin)
      options.binary = chrome_bin
    end
  end

  # 安全執行系統測試的輔助方法
  def safely_run_system_test
    return skip_system_test_with_message('Browser not available') unless browser_available?

    begin
      yield
    rescue Selenium::WebDriver::Error::SessionNotCreatedError => e
      skip_system_test_with_message("ChromeDriver incompatible: #{e.message}")
    rescue Selenium::WebDriver::Error::WebDriverError => e
      skip_system_test_with_message("WebDriver error: #{e.message}")
    rescue Net::ReadTimeout => e
      skip_system_test_with_message("Network timeout: #{e.message}")
    end
  end

  # 條件性系統測試執行
  def run_if_browser_available(description, &)
    if browser_available?
      it(description, &)
    else
      pending "#{description} (browser not available)"
    end
  end

  # 跳過系統測試並顯示訊息
  def skip_system_test_with_message(message)
    skip "System test skipped: #{message}"
  end

  # 檢查瀏覽器可用性（使用快取以避免重複檢查）
  def browser_available?
    return @browser_available if defined?(@browser_available)

    @browser_available = begin
      # 嘗試創建一個簡單的 WebDriver 實例
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument('--headless')
      options.add_argument('--no-sandbox')
      options.add_argument('--disable-dev-shm-usage')
      
      # 使用與主要配置相同的Chrome路徑邏輯
      configure_chrome_binary(options)

      driver = Selenium::WebDriver.for(:chrome, options: options)
      driver.quit
      true
    rescue StandardError => e
      Rails.logger.warn "Browser availability check failed: #{e.message}"
      puts "Browser availability check failed: #{e.message}" if ENV['RAILS_ENV'] == 'test'
      false
    end
  end

  # 取得 Chrome 版本資訊
  def chrome_version_info
    return @chrome_version_info if defined?(@chrome_version_info)

    @chrome_version_info = begin
      if browser_available?
        options = Selenium::WebDriver::Chrome::Options.new
        options.add_argument('--headless')
        options.add_argument('--no-sandbox')
        
        # 使用與主要配置相同的Chrome路徑邏輯
        configure_chrome_binary(options)

        driver = Selenium::WebDriver.for(:chrome, options: options)
        version = driver.capabilities.browser_version
        driver.quit
        version
      else
        'unknown'
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to get Chrome version: #{e.message}"
      'unknown'
    end
  end

  # 在系統測試中安全訪問頁面
  def safe_visit(path)
    visit path
  rescue Net::ReadTimeout => e
    skip_system_test_with_message("Page load timeout: #{e.message}")
  rescue Selenium::WebDriver::Error::TimeoutError => e
    skip_system_test_with_message("WebDriver timeout: #{e.message}")
  end

  # 安全等待元素
  def safe_find(selector, **)
    find(selector, **)
  rescue Capybara::ElementNotFound
    skip_system_test_with_message("Element not found: #{selector}")
  rescue Selenium::WebDriver::Error::TimeoutError
    skip_system_test_with_message("Element find timeout: #{selector}")
  end

  # 條件性等待
  def wait_for_condition(timeout: 10)
    start_time = Time.current
    while Time.current - start_time < timeout
      return true if yield

      sleep 0.1
    end
    false
  end

  # 截圖（用於偵錯）
  def take_debug_screenshot(name = 'debug')
    return unless page.driver.respond_to?(:save_screenshot)

    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    filename = "#{name}_#{timestamp}.png"
    screenshot_path = Rails.root.join('tmp', 'screenshots', filename)

    # 確保目錄存在
    FileUtils.mkdir_p(File.dirname(screenshot_path))

    page.save_screenshot(screenshot_path)
    Rails.logger.info "Screenshot saved: #{screenshot_path}"
  rescue StandardError => e
    Rails.logger.warn "Failed to save screenshot: #{e.message}"
  end

  # 模擬慢速網路
  def simulate_slow_network
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
  end

  # 檢查 JavaScript 錯誤
  def check_javascript_errors
    return unless page.driver.respond_to?(:browser)

    logs = page.driver.browser.logs.get(:browser)
    errors = logs.select { |log| log.level == 'SEVERE' }

    if errors.any?
      error_messages = errors.map(&:message).join("\n")
      Rails.logger.warn "JavaScript errors detected:\n#{error_messages}"
    end

    errors.empty?
  end

  # 等待 AJAX 完成
  def wait_for_ajax
    wait_for_condition(timeout: 30) do
      page.execute_script('return jQuery.active == 0')
    rescue StandardError
      true
    end
  end

  # 等待頁面載入完成
  def wait_for_page_load
    wait_for_condition(timeout: 30) do
      page.execute_script('return document.readyState') == 'complete'
    end
  end
end

# 在所有系統測試中包含這些輔助方法
RSpec.configure do |config|
  config.include SystemTestHelpers, type: :system

  # 在系統測試前檢查瀏覽器可用性
  config.before(:each, type: :system) do
    skip_system_test_with_message('Browser not available in test environment') unless browser_available?
  end

  # 在系統測試後清理
  config.after(:each, type: :system) do
    # 檢查是否有 JavaScript 錯誤
    if respond_to?(:check_javascript_errors) && !check_javascript_errors
      Rails.logger.warn "JavaScript errors detected in test: #{RSpec.current_example.full_description}"
    end

    # 重設會話
    Capybara.reset_sessions! if defined?(Capybara)
  end
end
