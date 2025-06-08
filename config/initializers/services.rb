# 載入所有服務類別
Dir[Rails.root.join('app', 'services', '*.rb')].each { |f| require f } 