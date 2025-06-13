#!/usr/bin/env ruby

puts "🧪 執行餐廳訂位系統完整測試套件"
puts "=" * 60

# 定義測試檔案
test_files = [
  'spec/models/reservation_policy_spec.rb',
  'spec/requests/admin/restaurant_settings/restaurant_settings_controller_spec.rb',
  'spec/requests/reservations_controller_spec.rb', 
  'spec/requests/restaurants_controller_spec.rb',
  'spec/system/admin/reservation_policies_system_spec.rb'
]

# 檢查測試檔案是否存在
puts "\n📋 檢查測試檔案存在性..."
missing_files = []
test_files.each do |file|
  if File.exist?(file)
    puts "  ✅ #{file}"
  else
    puts "  ❌ #{file}"
    missing_files << file
  end
end

if missing_files.any?
  puts "\n⚠️ 發現缺少的測試檔案:"
  missing_files.each { |file| puts "  - #{file}" }
  puts "\n請先創建這些檔案再執行測試。"
  exit 1
end

# 檢查Factory檔案
factory_file = 'spec/factories/reservation_policies.rb'
if File.exist?(factory_file)
  puts "  ✅ #{factory_file}"
else
  puts "  ⚠️ #{factory_file} 不存在，某些測試可能會失敗"
end

puts "\n🚀 開始執行測試..."

# 執行每個測試檔案
test_results = {}
test_files.each do |file|
  next unless File.exist?(file)
  
  puts "\n" + "─" * 60
  puts "🧪 執行: #{file}"
  puts "─" * 60
  
  start_time = Time.now
  result = system("rspec #{file} --format documentation")
  end_time = Time.now
  
  duration = (end_time - start_time).round(2)
  test_results[file] = {
    success: result,
    duration: duration
  }
  
  if result
    puts "✅ #{file} 通過 (#{duration}s)"
  else
    puts "❌ #{file} 失敗 (#{duration}s)"
  end
end

# 輸出總結
puts "\n" + "=" * 60
puts "📊 測試結果總結"
puts "=" * 60

passed_tests = test_results.select { |_, result| result[:success] }
failed_tests = test_results.select { |_, result| !result[:success] }
total_duration = test_results.values.sum { |result| result[:duration] }

puts "總共測試檔案: #{test_results.size}"
puts "通過: #{passed_tests.size}"
puts "失敗: #{failed_tests.size}"
puts "總執行時間: #{total_duration.round(2)}秒"

if failed_tests.any?
  puts "\n❌ 失敗的測試檔案:"
  failed_tests.each do |file, result|
    puts "  - #{file} (#{result[:duration]}s)"
  end
  
  puts "\n🔧 建議執行以下命令來查看詳細錯誤:"
  failed_tests.keys.each do |file|
    puts "  rspec #{file} --format documentation"
  end
else
  puts "\n🎉 所有測試都通過了！"
end

puts "\n📈 測試覆蓋的功能:"
puts "  ✅ ReservationPolicy 模型驗證和業務邏輯"
puts "  ✅ 訂位功能開關 (reservation_enabled)"
puts "  ✅ 手機號碼訂位次數限制"
puts "  ✅ 押金設定和計算"
puts "  ✅ 人數限制驗證"
puts "  ✅ 預約時間範圍限制"
puts "  ✅ 管理界面 Hotwire/Stimulus 功能"
puts "  ✅ API 端點保護機制"
puts "  ✅ 前端表單驗證和錯誤處理"
puts "  ✅ 系統測試 (瀏覽器互動)"

# 檢查是否有遺漏的測試場景
puts "\n🔍 檢查測試覆蓋率建議:"
puts "  📝 建議執行: bundle exec rspec --format html --out coverage/rspec_results.html"
puts "  📊 建議執行: bundle exec simplecov 來檢查程式碼覆蓋率"
puts "  🚀 建議執行: bundle exec brakeman 來檢查安全性問題"

exit failed_tests.any? ? 1 : 0 