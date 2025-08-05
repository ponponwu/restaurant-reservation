require 'database_cleaner/active_record'

RSpec.configure do |config|
  # 配置 Database Cleaner 策略
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
    
    # 為 Redis 清理做準備（如果使用 Redis）
    if defined?(Redis)
      Redis.current.flushdb if Rails.env.test?
    end
  end

  # 對每個測試使用事務策略
  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  # 對 System tests 使用 truncation 策略，因為它們可能跨多個線程
  config.around(:each, type: :system) do |example|
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.cleaning do
      example.run
    ensure
      DatabaseCleaner.strategy = :transaction
    end
  end

  # 在每個測試之前重置 FactoryBot 序列
  config.before(:each) do
    FactoryBot.reload if Rails.env.test?
  end
end