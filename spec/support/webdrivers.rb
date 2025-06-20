require 'webdrivers' if defined?(Webdrivers)

# 簡化的 webdrivers 配置
if defined?(Webdrivers)
  begin
    # 嘗試獲取 Chrome 版本資訊
    chrome_version = `google-chrome --version`.strip rescue nil
    chromedriver_version = `chromedriver --version`.strip rescue nil
    
    if defined?(Rails) && Rails.logger
      Rails.logger.info "Chrome version: #{chrome_version}" if chrome_version
      Rails.logger.info "ChromeDriver version: #{chromedriver_version}" if chromedriver_version
    end
    
    # 如果環境變數中指定了版本，使用該版本
    if ENV['CHROMEDRIVER_VERSION']
      puts "Using ChromeDriver version from ENV: #{ENV['CHROMEDRIVER_VERSION']}"
    end
    
  rescue => e
    puts "WebDriver setup warning: #{e.message}" if ENV['RAILS_ENV'] != 'production'
  end
end