#!/usr/bin/env ruby
# 檢查桌位狀況

require_relative 'config/environment'

restaurant = Restaurant.find_by(name: "Maan")
puts "🏪 餐廳: #{restaurant.name}"

puts "\n📊 所有桌位狀況："
restaurant.restaurant_tables.each do |table|
  puts "桌號: #{table.table_number}"
  puts "  容量: #{table.capacity} (最小: #{table.min_capacity}, 最大: #{table.max_capacity})"
  puts "  狀態: #{table.operational_status}"
  puts "  活躍: #{table.active?}"
  puts "  可併桌: #{table.can_combine?}"
  puts "  群組: #{table.table_group&.name}"
  puts
end

test_time = 2.hours.from_now
puts "🕒 測試時間: #{test_time.strftime('%Y/%m/%d %H:%M')}"

puts "\n🔍 A4 桌位詳細檢查："
a4_table = restaurant.restaurant_tables.find_by(table_number: 'A4')
if a4_table
  puts "桌號: #{a4_table.table_number}"
  puts "容量: #{a4_table.capacity}"
  puts "活躍: #{a4_table.active?}"
  puts "狀態: #{a4_table.operational_status}"
  puts "可併桌: #{a4_table.can_combine?}"
  puts "群組: #{a4_table.table_group&.name}"
  
  # 檢查該時段的可用性
  available = a4_table.available_for_datetime?(test_time)
  puts "該時段可用: #{available}"
  
  if !available
    conflicts = a4_table.find_conflicting_reservations(test_time)
    puts "衝突訂位:"
    conflicts.each do |res|
      puts "  - ID: #{res.id}, 客戶: #{res.customer_name}, 時間: #{res.reservation_datetime}, 狀態: #{res.status}"
    end
  end
else
  puts "找不到 A4 桌位"
end

puts "\n🧪 測試併桌分配邏輯："
allocator = ReservationAllocatorService.new({
  restaurant: restaurant,
  party_size: 4,
  adults: 4,
  children: 0,
  reservation_datetime: test_time,
  business_period_id: restaurant.business_periods.active.first.id
})

availability = allocator.check_availability
puts "可用性檢查結果:"
puts "  - 有可用桌位: #{availability[:has_availability]}"
puts "  - 可用桌位數: #{availability[:available_tables].count}"
puts "  - 可併桌: #{availability[:can_combine]}"
puts "  - 併桌選項數: #{availability[:combinable_tables].count}"

if availability[:combinable_tables].any?
  puts "併桌選項:"
  availability[:combinable_tables].each_with_index do |table, i|
    puts "  #{i+1}. #{table.table_number} (容量: #{table.capacity})"
  end
end 