#!/usr/bin/env ruby
# 桌位重複分配除錯腳本

require_relative 'config/environment'

puts "🔍 桌位重複分配除錯測試"
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

# 檢查現有訂位狀況
puts "\n📊 目前桌位使用狀況"
puts "-" * 30

test_time = 2.hours.from_now
puts "測試時間: #{test_time.strftime('%Y-%m-%d %H:%M')}"

restaurant.restaurant_tables.active.ordered.each do |table|
  conflicting_reservations = table.find_conflicting_reservations(test_time, 120)
  status = conflicting_reservations.any? ? "🔴 已佔用" : "🟢 可用"
  puts "桌位 #{table.table_number}: #{status}"
  
  if conflicting_reservations.any?
    conflicting_reservations.each do |res|
      puts "  └── #{res.customer_name} (ID: #{res.id}) #{res.reservation_datetime.strftime('%H:%M')} - #{(res.reservation_datetime + 120.minutes).strftime('%H:%M')}"
    end
  end
end

puts "\n🧪 重複分配測試"
puts "-" * 30

# 測試案例: 同時間建立多個訂位
reservations = []
allocated_tables = []

5.times do |i|
  puts "\n#{i+1}. 建立訂位 #{i+1}"
  
  reservation = Reservation.new(
    restaurant: restaurant,
    business_period: business_period,
    customer_name: "測試客戶#{i+1}",
    customer_phone: "091234567#{i}",
    customer_email: "test#{i}@example.com",
    party_size: 2,
    adults_count: 2,
    children_count: 0,
    reservation_datetime: test_time,
    status: :pending
  )
  
  # 檢查在分配前的可用桌位
  allocator = ReservationAllocatorService.new(reservation)
  availability = allocator.check_availability
  
  puts "  可用桌位: #{availability[:available_tables].map(&:table_number).join(', ')}"
  puts "  已保存訂位: #{reservations.count}"
  allocated_table_names = allocated_tables.compact.map do |t|
    if t.is_a?(Array)
      t.map(&:table_number).join('+')
    else
      t.table_number
    end
  end
  puts "  已分配桌位: #{allocated_table_names.join(', ')}"
  
  # 分配桌位
  allocated_table = allocator.allocate_table
  
  if allocated_table
    if allocated_table.is_a?(Array)
      puts "  ✅ 分配併桌: #{allocated_table.map(&:table_number).join(', ')}"
      reservation.table = allocated_table.first
    else
      puts "  ✅ 分配單桌: #{allocated_table.table_number}"
      reservation.table = allocated_table
    end
    
    # 保存訂位
    if reservation.save
      puts "  ✅ 訂位保存成功 (ID: #{reservation.id})"
      reservations << reservation
      allocated_tables << allocated_table
    else
      puts "  ❌ 訂位保存失敗: #{reservation.errors.full_messages.join(', ')}"
    end
  else
    puts "  ⚠️  無法分配桌位"
  end
end

puts "\n📋 重複檢查結果"
puts "-" * 30

# 檢查是否有重複分配
single_tables = allocated_tables.select { |t| !t.is_a?(Array) }
table_ids = single_tables.map(&:id)
duplicates = table_ids.group_by(&:itself).select { |_, v| v.size > 1 }

if duplicates.any?
  puts "❌ 發現重複分配的桌位:"
  duplicates.each do |table_id, instances|
    table = RestaurantTable.find(table_id)
    puts "  桌位 #{table.table_number} 被分配了 #{instances.size} 次"
  end
else
  puts "✅ 沒有發現重複分配"
end

# 檢查資料庫中的實際衝突
puts "\n🔍 資料庫衝突檢查"
puts "-" * 30

restaurant.restaurant_tables.active.each do |table|
  conflicting_reservations = Reservation.where(
    restaurant: restaurant,
    table: table,
    status: 'confirmed',
    reservation_datetime: test_time..(test_time + 5.minutes)
  )
  
  if conflicting_reservations.count > 1
    puts "❌ 桌位 #{table.table_number} 有 #{conflicting_reservations.count} 個衝突訂位:"
    conflicting_reservations.each do |res|
      puts "  - #{res.customer_name} (ID: #{res.id})"
    end
  end
end

# 清理測試資料
puts "\n🧹 清理測試資料"
puts "-" * 30

reservations.each do |reservation|
  if reservation.persisted?
    puts "刪除測試訂位: #{reservation.customer_name} (ID: #{reservation.id})"
    reservation.destroy
  end
end

puts "\n✅ 測試完成" 