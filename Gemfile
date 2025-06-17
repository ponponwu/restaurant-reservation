source "https://rubygems.org"

ruby "2.7.7"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.1.5", ">= 7.1.5.1"

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Bundle and transpile JavaScript [https://github.com/rails/jsbundling-rails]
gem "jsbundling-rails"

# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"

# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Bundle and process CSS [https://github.com/rails/cssbundling-rails]
gem "cssbundling-rails"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Redis adapter to run Action Cable in production
gem "redis", ">= 4.0.1"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mswin mswin64 mingw x64_mingw jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# 認證與授權
gem 'devise', '~> 4.9'
gem 'cancancan', '~> 3.5'

# 資料處理與分頁
gem 'pagy', '~> 6.2'
gem 'ransack', '~> 3.2'
gem 'chartkick', '~> 5.0'
gem 'groupdate', '~> 5.2'

# 背景任務
gem 'sidekiq', '~> 7.0'    # 使用支援 rack 3 的版本
gem 'sidekiq-cron', '~> 1.12'

# 通知系統
gem 'twilio-ruby', '~> 7.6' # SMS 通知

# 檔案處理與匯出
gem 'caxlsx', '~> 4.1'      # Excel 匯出
gem 'caxlsx_rails', '~> 0.6'
gem 'prawn', '~> 2.4'       # PDF 產生

# 其他實用工具
gem 'friendly_id', '~> 5.5' # 友善 URL
gem 'kaminari', '~> 1.2'    # 分頁（備用）
gem 'chronic', '~> 0.10'    # 時間解析

# 資料驗證與格式化
gem 'validates_email_format_of', '~> 1.7'
gem 'phonelib', '~> 0.8'    # 電話號碼驗證

# 中文支援
gem 'rails-i18n', '~> 7.0'

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri mingw x64_mingw ]
  gem 'pry-byebug'
  
  # 測試框架
  gem 'rspec-rails', '~> 6.0'
  gem 'factory_bot_rails', '~> 6.2'
  gem 'capybara', '>= 3.39'
  gem 'selenium-webdriver', '>= 4.9.0'
  gem 'webdrivers'
  
  # CI/CD 相關工具
  gem 'rubocop', '~> 1.57', require: false
  gem 'rubocop-rails', '~> 2.21', require: false
  gem 'rubocop-rspec', '~> 2.24', require: false
  gem 'rubocop-performance', '~> 1.19', require: false
  gem 'brakeman', '~> 6.0', require: false
  gem 'bundler-audit', '~> 0.9', require: false
  gem 'simplecov', '~> 0.22', require: false
  gem 'rspec_junit_formatter', '~> 0.6', require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end
