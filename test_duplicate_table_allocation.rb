#!/usr/bin/env ruby
# 測試重複桌位分配問題

require_relative 'config/environment'

puts "🔍 測試重複桌位分配問題"
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

# 清理現有測試資料
puts "\n🧹 清理現有測試資料"
restaurant.reservations.where("customer_name LIKE ?", "重複測試%").destroy_all

# 檢查四人桌數量
four_person_tables = restaurant.restaurant_tables.active.where(capacity: 4)
puts "\n📊 四人桌統計："
puts "  總數: #{four_person_tables.count}"
four_person_tables.each do |table|
  puts "  - 桌號: #{table.table_number}, 容量: #{table.capacity}, 最小: #{table.min_capacity}, 最大: #{table.max_capacity}"
end

test_time = 2.hours.from_now
puts "\n🕒 測試時間: #{test_time.strftime('%Y/%m/%d %H:%M')}"

# 測試第一次訂位
puts "\n🧪 第一次訂位測試 (4人)"
puts "-" * 30

# 使用前台控制器相同的方式檢查可用性
allocator1 = ReservationAllocatorService.new({
  restaurant: restaurant,
  party_size: 4,
  adults: 4,
  children: 0,
  reservation_datetime: test_time,
  business_period_id: business_period.id
})

availability1 = allocator1.check_availability
puts "可用性檢查結果:"
puts "  - 有可用桌位: #{availability1[:has_availability]}"
puts "  - 可用桌位數: #{availability1[:available_tables].count}"
puts "  - 可併桌: #{availability1[:can_combine]}"

if availability1[:has_availability]
  allocated_table1 = allocator1.allocate_table
  puts "分配的桌位: #{allocated_table1.is_a?(Array) ? allocated_table1.map(&:table_number).join(', ') : allocated_table1&.table_number}"
  
  # 建立第一個訂位
  reservation1 = Reservation.create!(
    restaurant: restaurant,
    business_period: business_period,
    customer_name: "重複測試客戶1",
    customer_phone: "0912345001",
    customer_email: "test1@example.com",
    party_size: 4,
    adults_count: 4,
    children_count: 0,
    reservation_datetime: test_time,
    status: :confirmed,
    table: allocated_table1.is_a?(Array) ? allocated_table1.first : allocated_table1
  )
  
  puts "✅ 第一個訂位建立成功 (ID: #{reservation1.id})"
  puts "   分配桌位: #{reservation1.table&.table_number}"
else
  puts "❌ 沒有可用桌位"
  exit 1
end

# 測試第二次訂位（應該失敗或分配不同桌位）
puts "\n🧪 第二次訂位測試 (4人，相同時間)"
puts "-" * 30

# 重新檢查可用性
allocator2 = ReservationAllocatorService.new({
  restaurant: restaurant,
  party_size: 4,
  adults: 4,
  children: 0,
  reservation_datetime: test_time,
  business_period_id: business_period.id
})

availability2 = allocator2.check_availability
puts "可用性檢查結果:"
puts "  - 有可用桌位: #{availability2[:has_availability]}"
puts "  - 可用桌位數: #{availability2[:available_tables].count}"
puts "  - 可併桌: #{availability2[:can_combine]}"

if availability2[:has_availability]
  allocated_table2 = allocator2.allocate_table
  puts "分配的桌位: #{allocated_table2.is_a?(Array) ? allocated_table2.map(&:table_number).join(', ') : allocated_table2&.table_number}"
  
  # 檢查是否分配到相同桌位
  if allocated_table2.is_a?(Array)
    table2_numbers = allocated_table2.map(&:table_number).sort
    table1_number = [reservation1.table&.table_number].compact
    conflict = !(table2_numbers & table1_number).empty?
  else
    conflict = allocated_table2&.table_number == reservation1.table&.table_number
  end
  
  if conflict
    puts "⚠️  警告: 分配到相同桌位！這是重複分配問題"
  else
    puts "✅ 分配到不同桌位，沒有衝突"
  end
  
  # 嘗試建立第二個訂位
  begin
    reservation2 = Reservation.create!(
      restaurant: restaurant,
      business_period: business_period,
      customer_name: "重複測試客戶2",
      customer_phone: "0912345002",
      customer_email: "test2@example.com",
      party_size: 4,
      adults_count: 4,
      children_count: 0,
      reservation_datetime: test_time,
      status: :confirmed,
      table: allocated_table2.is_a?(Array) ? allocated_table2.first : allocated_table2
    )
    
    puts "✅ 第二個訂位建立成功 (ID: #{reservation2.id})"
    puts "   分配桌位: #{reservation2.table&.table_number}"
  rescue => e
    puts "❌ 第二個訂位建立失敗: #{e.message}"
  end
else
  puts "✅ 正確：沒有可用桌位，系統正確拒絕了重複訂位"
end

# 檢查最終狀態
puts "\n📊 最終桌位分配狀態"
puts "-" * 30

test_reservations = restaurant.reservations.where("customer_name LIKE ?", "重複測試%")
puts "測試訂位總數: #{test_reservations.count}"

test_reservations.each_with_index do |res, i|
  puts "#{i+1}. 客戶: #{res.customer_name}"
  puts "   時間: #{res.reservation_datetime.strftime('%Y/%m/%d %H:%M')}"
  puts "   桌位: #{res.table&.table_number || '無'}"
  puts "   狀態: #{res.status}"
  
  # 檢查是否有併桌
  if res.table_combination.present?
    combination_tables = res.table_combination.restaurant_tables.pluck(:table_number)
    puts "   併桌: #{combination_tables.join(', ')}"
  end
  puts
end

# 檢查桌位衝突
puts "🔍 桌位衝突檢查："
table_assignments = test_reservations.map do |res|
  tables = []
  tables << res.table&.table_number if res.table.present?
  if res.table_combination.present?
    tables.concat(res.table_combination.restaurant_tables.pluck(:table_number))
  end
  { reservation_id: res.id, customer: res.customer_name, tables: tables.compact }
end

conflicts = []
table_assignments.each_with_index do |assignment1, i|
  table_assignments[(i+1)..-1].each do |assignment2|
    overlapping_tables = assignment1[:tables] & assignment2[:tables]
    if overlapping_tables.any?
      conflicts << {
        reservation1: assignment1,
        reservation2: assignment2,
        conflicting_tables: overlapping_tables
      }
    end
  end
end

if conflicts.any?
  puts "❌ 發現 #{conflicts.count} 個桌位衝突："
  conflicts.each do |conflict|
    puts "  - #{conflict[:reservation1][:customer]} vs #{conflict[:reservation2][:customer]}"
    puts "    衝突桌位: #{conflict[:conflicting_tables].join(', ')}"
  end
else
  puts "✅ 沒有發現桌位衝突"
end

# 清理測試資料
puts "\n🧹 清理測試資料"
test_reservations.destroy_all
puts "測試完成" 