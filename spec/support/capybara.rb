require 'capybara/rails'
require 'capybara/rspec'
require 'selenium/webdriver'

# 確保 SystemTestHelpers 被載入以使用 configure_chrome_binary 方法
require_relative 'system_test_helpers'

# 包含 SystemTestHelpers 以便使用 configure_chrome_binary 方法
include SystemTestHelpers

# 配置 Capybara
Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new

  # 基本選項
  options.add_argument('--headless')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-gpu')
  options.add_argument('--window-size=1400,1400')
  options.add_argument('--disable-extensions')
  options.add_argument('--disable-plugins')
  options.add_argument('--disable-images')
  options.add_argument('--disable-web-security')
  options.add_argument('--allow-running-insecure-content')

  # 效能優化選項
  options.add_argument('--aggressive-cache-discard')
  options.add_argument('--memory-pressure-off')
  options.add_argument('--disable-background-timer-throttling')
  options.add_argument('--disable-renderer-backgrounding')
  options.add_argument('--disable-backgrounding-occluded-windows')

  # 相容性選項
  options.add_argument('--disable-features=TranslateUI')
  options.add_argument('--disable-ipc-flooding-protection')

  # 配置 Chrome 二進位路徑
  configure_chrome_binary(options)

  Capybara::Selenium::Driver.new(
    app,
    browser: :chrome,
    options: options
  )
end

# 配置有頭模式的 Chrome（用於偵錯）
Capybara.register_driver :chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--window-size=1400,1400')
  options.add_argument('--disable-web-security')
  options.add_argument('--allow-running-insecure-content')

  # 配置 Chrome 二進位路徑
  configure_chrome_binary(options)

  Capybara::Selenium::Driver.new(
    app,
    browser: :chrome,
    options: options
  )
end

# 設定預設驅動程式
Capybara.default_driver = :rack_test
Capybara.javascript_driver = :headless_chrome

# 基本配置 - 優化等待時間以提升測試速度
Capybara.default_max_wait_time = 5
# 使用隨機端口避免衝突
Capybara.server_port = nil  # 讓 Capybara 自動選擇可用端口
Capybara.app_host = nil     # 讓 Capybara 自動設定

# 伺服器配置
Capybara.server = :puma, { Silent: true }

# 處理 ChromeDriver 版本不相容的問題
RSpec.configure do |config|
  config.before(:each, type: :system) do
    # 嘗試偵測可用的 Chrome 版本

    driven_by :headless_chrome
  rescue Selenium::WebDriver::Error::SessionNotCreatedError => e
    raise e unless e.message.include?('ChromeDriver only supports Chrome version')

    # 如果 ChromeDriver 不相容，跳過系統測試
    skip "ChromeDriver version incompatible: #{e.message}"
  end

  config.before(:each, :js, type: :system) do
    driven_by :headless_chrome
  rescue Selenium::WebDriver::Error::SessionNotCreatedError => e
    raise e unless e.message.include?('ChromeDriver only supports Chrome version')

    skip "ChromeDriver version incompatible: #{e.message}"
  end

  # 允許在特定環境下使用有頭模式進行偵錯
  config.before(:each, :debug, type: :system) do
    driven_by :chrome
  end

  config.after(:each, type: :system) do
    # 清理截圖和其他資源
    Capybara.reset_sessions!
  end
end

# 環境特定的配置
if ENV['CI'] || ENV['GITHUB_ACTIONS']
  # CI 環境配置 - 減少等待時間提升CI速度
  Capybara.default_max_wait_time = 15
  Capybara.server_port = 3002

  # 在 CI 中使用更穩定的設定
  Capybara.register_driver :ci_chrome do |app|
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--disable-gpu')
    options.add_argument('--window-size=1920,1080')
    options.add_argument('--disable-extensions')
    options.add_argument('--disable-web-security')
    options.add_argument('--remote-debugging-port=9222')

    Capybara::Selenium::Driver.new(
      app,
      browser: :chrome,
      options: options
    )
  end

  Capybara.javascript_driver = :ci_chrome
end

# 提供降級選項：如果 Chrome 不可用，使用 rack_test
def safely_driven_by(driver)
  driven_by driver
rescue Selenium::WebDriver::Error::WebDriverError => e
  Rails.logger.warn "WebDriver error: #{e.message}, falling back to rack_test"
  driven_by :rack_test
end

# 瀏覽器路徑配置輔助方法
def configure_chrome_binary(options)
  chrome_bin = ENV.fetch('CHROME_BIN', nil)
  if chrome_bin.nil?
    # 優先使用正常的 Google Chrome（版本較新）
    regular_chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    options.binary = regular_chrome if File.exist?(regular_chrome)
    # 如果找不到正常版本，讓 Selenium 使用預設路徑
  elsif File.exist?(chrome_bin)
    options.binary = chrome_bin
  end
end

# 輔助方法：檢查瀏覽器是否可用
def browser_available?
  # 嘗試創建一個簡單的 WebDriver 實例
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')

  configure_chrome_binary(options)

  begin
    driver = Selenium::WebDriver.for(:chrome, options: options)
    driver.quit
    true
  rescue StandardError => e
    Rails.logger.warn "Browser availability check failed: #{e.message}" if defined?(Rails)
    puts "Browser not available: #{e.message}" if ENV['RAILS_ENV'] == 'test'
    false
  end
end

# 條件性系統測試支援
if defined?(RSpec)
  RSpec.configure do |config|
    # 在測試套件開始前檢查瀏覽器可用性
    config.before(:suite) do
      if RSpec.configuration.files_to_run.any? { |f| f.include?('spec/system') }
        if browser_available?
          puts "\n✅ Browser compatibility verified. System tests will run normally."
        else
          puts "\n⚠️  Warning: Browser not available for system tests. Individual tests will be skipped."
          puts '   Please ensure Chrome and ChromeDriver versions are compatible.'
        end
      end
    end
  end
end
