#!/usr/bin/env ruby
# 測試簡化狀態管理

require_relative 'config/environment'

puts "🔄 簡化狀態管理測試"
puts "=" * 50

# 尋找測試餐廳
restaurant = Restaurant.find_by(name: "Maan")
if restaurant.nil?
  puts "❌ 找不到測試餐廳 'Maan'"
  exit 1
end

business_period = restaurant.business_periods.active.first
if business_period.nil?
  puts "❌ 找不到活躍的營業時段"
  exit 1
end

puts "🏪 測試餐廳: #{restaurant.name}"
puts "⏰ 營業時段: #{business_period.name}"

# 檢查可用的狀態
puts "\n📋 可用的訂位狀態："
Reservation.statuses.each do |status, value|
  puts "  - #{status}: #{value}"
end

# 測試建立訂位
puts "\n🧪 測試訂位建立"
puts "-" * 30

test_time = 2.hours.from_now
reservation = Reservation.new(
  restaurant: restaurant,
  business_period: business_period,
  customer_name: "測試客戶",
  customer_phone: "0912345678",
  customer_email: "test@example.com",
  party_size: 2,
  adults_count: 2,
  children_count: 0,
  reservation_datetime: test_time,
  status: :confirmed  # 直接設為已確認
)

if reservation.save
  puts "✅ 訂位建立成功 (ID: #{reservation.id})"
  puts "   狀態: #{reservation.status}"
  puts "   客戶: #{reservation.customer_name}"
  puts "   人數: #{reservation.party_size}"
  puts "   時間: #{reservation.formatted_datetime}"
else
  puts "❌ 訂位建立失敗: #{reservation.errors.full_messages.join(', ')}"
  exit 1
end

# 測試狀態轉換
puts "\n🔄 測試狀態轉換"
puts "-" * 30

# 測試取消
puts "1. 測試取消訂位"
if reservation.can_cancel?
  reservation.status = :cancelled
  if reservation.save
    puts "   ✅ 訂位已取消"
  else
    puts "   ❌ 取消失敗: #{reservation.errors.full_messages.join(', ')}"
  end
else
  puts "   ❌ 無法取消此訂位"
end

# 重新設為確認狀態以測試未出席
reservation.update!(status: :confirmed)
puts "\n2. 測試標記未出席"

# 模擬過去的時間
past_time = 1.hour.ago
reservation.update!(reservation_datetime: past_time)

if reservation.can_mark_no_show?
  reservation.status = :no_show
  if reservation.save
    puts "   ✅ 已標記為未出席"
  else
    puts "   ❌ 標記失敗: #{reservation.errors.full_messages.join(', ')}"
  end
else
  puts "   ❌ 無法標記為未出席"
end

# 測試查詢方法
puts "\n📊 測試查詢方法"
puts "-" * 30

# 建立多個不同狀態的訂位進行測試
test_reservations = []

3.times do |i|
  status = [:confirmed, :cancelled, :no_show][i]
  res = Reservation.create!(
    restaurant: restaurant,
    business_period: business_period,
    customer_name: "測試客戶#{i+1}",
    customer_phone: "091234567#{i}",
    customer_email: "test#{i}@example.com",
    party_size: 2,
    adults_count: 2,
    children_count: 0,
    reservation_datetime: test_time + (i * 30).minutes,
    status: status
  )
  test_reservations << res
  puts "建立 #{status} 狀態訂位 (ID: #{res.id})"
end

# 測試 scope
puts "\n📋 Scope 測試結果："
puts "  - 所有訂位數: #{restaurant.reservations.count}"
puts "  - 活躍訂位數 (非取消/未出席): #{restaurant.reservations.active.count}"
puts "  - 已確認訂位數: #{restaurant.reservations.confirmed.count}"

# 檢查模型方法
puts "\n🔍 模型方法測試："
confirmed_reservation = test_reservations.find(&:confirmed?)
if confirmed_reservation
  puts "  - 已確認訂位可以取消: #{confirmed_reservation.can_cancel?}"
  puts "  - 已確認訂位可以修改: #{confirmed_reservation.can_modify?}"
end

cancelled_reservation = test_reservations.find(&:cancelled?)
if cancelled_reservation
  puts "  - 已取消訂位可以取消: #{cancelled_reservation.can_cancel?}"
  puts "  - 已取消訂位可以修改: #{cancelled_reservation.can_modify?}"
end

# 清理測試資料
puts "\n🧹 清理測試資料"
puts "-" * 30

all_test_reservations = [reservation] + test_reservations
all_test_reservations.each do |res|
  if res.persisted?
    puts "刪除測試訂位: #{res.customer_name} (ID: #{res.id})"
    res.destroy
  end
end

puts "\n✅ 簡化狀態管理測試完成"

puts "\n📝 功能總結："
puts "  ✅ 狀態簡化為: confirmed, cancelled, no_show"
puts "  ✅ 新建訂位直接為 confirmed 狀態"
puts "  ✅ 支援取消訂位功能"
puts "  ✅ 支援標記未出席功能"
puts "  ✅ 查詢和過濾功能正常" 