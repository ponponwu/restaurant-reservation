require 'webdrivers' if defined?(Webdrivers)

# 簡化的 webdrivers 配置
if defined?(Webdrivers)
  begin
    # 嘗試獲取 Chrome 版本資訊
    chrome_version = begin
      `google-chrome --version`.strip
    rescue StandardError
      nil
    end
    chromedriver_version = begin
      `chromedriver --version`.strip
    rescue StandardError
      nil
    end

    if defined?(Rails) && Rails.logger
      Rails.logger.info "Chrome version: #{chrome_version}" if chrome_version
      Rails.logger.info "ChromeDriver version: #{chromedriver_version}" if chromedriver_version
    end

    # 如果環境變數中指定了版本，使用該版本
    puts "Using ChromeDriver version from ENV: #{ENV['CHROMEDRIVER_VERSION']}" if ENV['CHROMEDRIVER_VERSION']
  rescue StandardError => e
    puts "WebDriver setup warning: #{e.message}" if ENV['RAILS_ENV'] != 'production'
  end
end
