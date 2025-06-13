#!/usr/bin/env ruby

require_relative 'config/environment'

puts "🧪 測試 Hotwire 訂位政策功能"
puts "=" * 50

# 找到第一個餐廳
restaurant = Restaurant.first
unless restaurant
  puts "❌ 找不到餐廳記錄"
  exit 1
end

puts "📍 使用餐廳: #{restaurant.name}"

# 檢查訂位政策
policy = restaurant.reservation_policy
unless policy
  puts "❌ 找不到訂位政策記錄"
  exit 1
end

puts "✅ 找到訂位政策記錄"
puts "當前狀態:"
puts "  - 訂位功能: #{policy.reservation_enabled? ? '啟用' : '停用'}"
puts "  - 押金要求: #{policy.deposit_required? ? '啟用' : '停用'}"

# 測試切換訂位功能
puts "\n🔧 測試訂位功能切換..."
original_state = policy.reservation_enabled?
new_state = !original_state

# 更新狀態
policy.update!(reservation_enabled: new_state)
puts "  - 更新後狀態: #{policy.reservation_enabled? ? '啟用' : '停用'}"

# 測試切換押金功能
puts "\n💰 測試押金功能切換..."
original_deposit = policy.deposit_required?
new_deposit = !original_deposit

policy.update!(deposit_required: new_deposit)
puts "  - 更新後押金狀態: #{policy.deposit_required? ? '啟用' : '停用'}"

# 恢復原始狀態
puts "\n↩️ 恢復原始狀態..."
policy.update!(
  reservation_enabled: original_state,
  deposit_required: original_deposit
)

puts "✅ 資料庫操作測試完成"

# 檢查 Stimulus 控制器檔案
controller_path = Rails.root.join('app', 'javascript', 'controllers', 'reservation_policy_controller.js')
if File.exist?(controller_path)
  puts "✅ Stimulus 控制器檔案存在: #{controller_path}"
else
  puts "❌ Stimulus 控制器檔案不存在: #{controller_path}"
end

# 檢查 application.js 是否有註冊控制器
app_js_path = Rails.root.join('app', 'javascript', 'application.js')
if File.exist?(app_js_path)
  content = File.read(app_js_path)
  if content.include?('reservation-policy')
    puts "✅ Stimulus 控制器已在 application.js 中註冊"
  else
    puts "⚠️ Stimulus 控制器尚未在 application.js 中註冊"
    puts "需要手動添加以下程式碼到 application.js:"
    puts "import ReservationPolicyController from './controllers/reservation_policy_controller'"
    puts "application.register('reservation-policy', ReservationPolicyController)"
  end
else
  puts "❌ application.js 檔案不存在"
end

# 檢查視圖檔案
view_path = Rails.root.join('app', 'views', 'admin', 'restaurant_settings', 'restaurant_settings', 'reservation_policies.html.erb')
if File.exist?(view_path)
  content = File.read(view_path)
  if content.include?('data-controller="reservation-policy"')
    puts "✅ 視圖檔案已設定 Stimulus 控制器"
  else
    puts "❌ 視圖檔案尚未設定 Stimulus 控制器"
  end
  
  if content.include?('<script>')
    puts "⚠️ 視圖檔案仍包含內聯 JavaScript"
  else
    puts "✅ 視圖檔案已移除內聯 JavaScript"
  end
else
  puts "❌ 視圖檔案不存在"
end

puts "\n🎯 Hotwire 實作檢查完成"
puts "=" * 50 