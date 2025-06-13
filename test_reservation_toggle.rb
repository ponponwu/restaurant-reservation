#!/usr/bin/env ruby
require_relative 'config/environment'

puts "測試訂位功能開關..."
puts "="*50

# 找到第一個餐廳
restaurant = Restaurant.first
if restaurant.nil?
  puts "❌ 沒有找到餐廳資料"
  exit 1
end

puts "🍽️  餐廳: #{restaurant.name}"

# 獲取或建立 reservation_policy
policy = restaurant.reservation_policy || restaurant.build_reservation_policy
if policy.new_record?
  policy.save!
  puts "✅ 建立了新的預約規則"
end

puts "\n目前狀態："
puts "訂位功能開啟: #{policy.reservation_enabled?}"

# 測試關閉訂位功能
puts "\n🔄 測試關閉訂位功能..."
policy.update!(reservation_enabled: false)
policy.reload
puts "✅ 更新成功，新狀態: 訂位功能開啟 = #{policy.reservation_enabled?}"

# 測試前台檢查
puts "\n🌐 測試前台檢查..."
puts "accepts_online_reservations? = #{policy.accepts_online_reservations?}"

# 測試重新開啟
puts "\n🔄 測試重新開啟訂位功能..."
policy.update!(reservation_enabled: true)
policy.reload
puts "✅ 更新成功，新狀態: 訂位功能開啟 = #{policy.reservation_enabled?}"
puts "accepts_online_reservations? = #{policy.accepts_online_reservations?}"

puts "\n🎉 所有測試完成！" 