source 'https://rubygems.org'

ruby '3.2.2'

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem 'rails', '~> 8.0'

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem 'sprockets-rails'

# Use postgresql as the database for Active Record
gem 'pg', '~> 1.1'

# Use the Puma web server [https://github.com/puma/puma]
gem 'puma', '>= 5.0'

# Bundle and transpile JavaScript [https://github.com/rails/jsbundling-rails]
gem 'jsbundling-rails'

# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem 'turbo-rails'

# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem 'stimulus-rails'

# Bundle and process CSS [https://github.com/rails/cssbundling-rails]
gem 'cssbundling-rails'

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem 'jbuilder'

# Redis removed - using PostgreSQL-based solutions instead

# PostgreSQL advisory locks for distributed locking
gem 'with_advisory_lock', '~> 4.6'

# Rails 8 Solid Cache for PostgreSQL-based caching
gem 'solid_cache', '~> 1.0'

# Rails 8 Solid Queue for background job processing
gem 'solid_queue', '~> 1.0'

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %i[mswin mswin64 mingw x64_mingw jruby]

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem 'image_processing', '~> 1.2'

# 認證與授權
gem 'cancancan', '~> 3.5'
gem 'devise', '~> 4.9'

# 資料處理與分頁
gem 'chartkick', '~> 5.0'
gem 'groupdate', '~> 5.2'
gem 'pagy', '~> 6.2'
gem 'ransack', '~> 4.3'

# 背景任務
# gem 'sidekiq', '~> 7.0'    # 使用支援 rack 3 的版本
# gem 'sidekiq-cron', '~> 1.12'

# 通知系統
# gem 'twilio-ruby', '~> 7.6' # SMS 通知

# 檔案處理與匯出
gem 'caxlsx', '~> 4.1'      # Excel 匯出
gem 'caxlsx_rails', '~> 0.6'
gem 'prawn', '~> 2.4'       # PDF 產生

# 其他實用工具
gem 'chronic', '~> 0.10'    # 時間解析
gem 'friendly_id', '~> 5.5' # 友善 URL
gem 'kaminari', '~> 1.2'    # 分頁（備用）

# 資料驗證與格式化
gem 'phonelib', '~> 0.8' # 電話號碼驗證
gem 'validates_email_format_of', '~> 1.7'

# 中文支援
gem 'rails-i18n', '~> 8.0'

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'debug', platforms: %i[mri mingw x64_mingw]
  gem 'pry-byebug'

  # 測試框架
  gem 'capybara', '~> 3.40'
  gem 'factory_bot_rails', '~> 6.2'
  gem 'rails-controller-testing'
  gem 'rspec-rails', '~> 6.0'
  gem 'selenium-webdriver', '>= 4.9.0'
  gem 'webdrivers'

  # CI/CD 相關工具
  gem 'brakeman', '~> 5.4', require: false
  gem 'bundler-audit', '~> 0.9', require: false
  gem 'rspec_junit_formatter', '~> 0.6', require: false
  gem 'rubocop', '~> 1.56', require: false
  gem 'rubocop-performance', '~> 1.18', require: false
  gem 'rubocop-rails', '~> 2.20', require: false
  gem 'rubocop-rspec', '~> 2.23', require: false
  gem 'simplecov', '~> 0.22', require: false
  gem 'timecop'
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem 'web-console'

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end

gem 'shoulda-matchers', '~> 6.5', group: :test
