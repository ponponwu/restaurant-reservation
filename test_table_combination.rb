#!/usr/bin/env ruby
require_relative 'config/environment'

puts "=== 餐廳訂位系統 - 併桌功能測試 ==="
puts

# 找到測試餐廳
restaurant = Restaurant.first
if restaurant.nil?
  puts "❌ 找不到測試餐廳"
  exit 1
end

puts "🏪 測試餐廳：#{restaurant.name}"
puts "📍 地址：#{restaurant.address}"
puts

# 檢查用餐時間設定
puts "⏰ 用餐時間設定："
puts "   預設用餐時間：#{restaurant.dining_duration_minutes} 分鐘"
puts "   緩衝時間：#{restaurant.buffer_time_minutes || 15} 分鐘"
puts "   總佔用時間：#{restaurant.dining_duration_with_buffer} 分鐘"
puts "   允許併桌：#{restaurant.can_combine_tables? ? '✅ 是' : '❌ 否'}"
puts "   最大併桌數：#{restaurant.max_tables_per_combination} 張桌位"
puts

# 檢查桌位狀況
puts "🪑 桌位狀況："
total_tables = restaurant.restaurant_tables.active.count
combinable_tables = restaurant.restaurant_tables.active.where(can_combine: true).count
puts "   總桌位數：#{total_tables}"
puts "   可併桌桌位：#{combinable_tables}"
puts

# 顯示桌位詳情
restaurant.restaurant_tables.active.includes(:table_group).each do |table|
  puts "   #{table.table_number}：#{table.capacity}人 (#{table.table_group.name}) #{table.can_combine? ? '可併桌' : '不可併桌'}"
end
puts

# 測試時間和營業時段
test_time = 1.day.from_now.change(hour: 18, min: 0)
business_period = restaurant.business_periods.active.first
puts "🕕 測試時間：#{test_time.strftime('%Y-%m-%d %H:%M')}"
puts "📅 營業時段：#{business_period&.name || '無'}"
puts

# 測試不同人數的訂位需求
test_cases = [
  { party_size: 2, description: "2人小聚" },
  { party_size: 4, description: "4人家庭" },
  { party_size: 6, description: "6人聚餐" },
  { party_size: 8, description: "8人聚會" }
]

test_cases.each do |test_case|
  puts "👥 測試 #{test_case[:description]} (#{test_case[:party_size]}人)："
  
  # 建立測試訂位
  reservation = Reservation.new(
    restaurant: restaurant,
    business_period: business_period,
    customer_name: "測試客戶#{test_case[:party_size]}人",
    customer_phone: "091234567#{test_case[:party_size]}",
    party_size: test_case[:party_size],
    adults_count: test_case[:party_size],
    children_count: 0,
    reservation_datetime: test_time + (test_case[:party_size] * 5).minutes
  )
  
  # 使用分配服務
  allocator = ReservationAllocatorService.new(reservation)
  
  # 檢查可用性
  availability = allocator.check_availability
  puts "   可用性檢查："
  puts "     有可用桌位：#{availability[:has_availability] ? '✅' : '❌'}"
  puts "     可併桌：#{availability[:can_combine] ? '✅' : '❌'}"
  puts "     可用桌位：#{availability[:available_tables].map(&:table_number).join(', ')}"
  puts "     可併桌桌位：#{availability[:combinable_tables].map(&:table_number).join(', ')}"
  
  # 嘗試分配桌位
  allocated_table = allocator.allocate_table
  
  if allocated_table
    # 將分配的桌位設定到訂位中
    reservation.table = allocated_table unless reservation.table_combination.present?
    
    puts "   ✅ 分配成功："
    if reservation.table_combination.present?
      combination = reservation.table_combination
      puts "     併桌方案：#{combination.restaurant_tables.map(&:table_number).join(' + ')}"
      puts "     總容量：#{combination.total_capacity}人"
      puts "     效率：#{(test_case[:party_size].to_f / combination.total_capacity * 100).round(1)}%"
    else
      puts "     單一桌位：#{allocated_table.table_number}"
      puts "     桌位容量：#{allocated_table.capacity}人"
    end
  else
    puts "   ❌ 分配失敗：無法找到合適的桌位"
  end
  
  puts
end

# 測試時間衝突
puts "⚠️  測試時間衝突："
puts "   建立一個6點的4人訂位..."

# 建立第一個訂位
first_reservation = restaurant.reservations.create!(
  business_period: business_period,
  customer_name: "張先生",
  customer_phone: "0912345678",
  party_size: 4,
  adults_count: 4,
  children_count: 0,
  reservation_datetime: test_time,
  status: :confirmed
)

# 分配桌位
allocator1 = ReservationAllocatorService.new(first_reservation)
table1 = allocator1.allocate_table
first_reservation.update!(table: table1) if table1

puts "   第一個訂位：#{first_reservation.customer_name} #{first_reservation.party_size}人"
puts "   分配桌位：#{table1&.table_number || '無'}"
puts "   佔用時間：#{first_reservation.reservation_datetime.strftime('%H:%M')} - #{first_reservation.estimated_end_time.strftime('%H:%M')}"
puts

# 測試8點的訂位（應該可以成功）
puts "   測試8點的4人訂位（應該可以成功）..."
second_reservation = Reservation.new(
  restaurant: restaurant,
  business_period: business_period,
  customer_name: "王小姐",
  customer_phone: "0987654321",
  party_size: 4,
  adults_count: 4,
  children_count: 0,
  reservation_datetime: test_time + 2.hours
)

allocator2 = ReservationAllocatorService.new(second_reservation)
availability2 = allocator2.check_availability
table2 = allocator2.allocate_table

puts "   第二個訂位：#{second_reservation.customer_name} #{second_reservation.party_size}人"
puts "   時間：#{second_reservation.reservation_datetime.strftime('%H:%M')}"
puts "   可用性：#{availability2[:has_availability] ? '✅ 可訂位' : '❌ 無法訂位'}"
puts "   分配結果：#{table2&.table_number || '無可用桌位'}"
puts

# 測試7點的訂位（可能衝突）
puts "   測試7點的4人訂位（可能衝突）..."
third_reservation = Reservation.new(
  restaurant: restaurant,
  business_period: business_period,
  customer_name: "李先生",
  customer_phone: "0955123456",
  party_size: 4,
  adults_count: 4,
  children_count: 0,
  reservation_datetime: test_time + 1.hour
)

allocator3 = ReservationAllocatorService.new(third_reservation)
availability3 = allocator3.check_availability
table3 = allocator3.allocate_table

puts "   第三個訂位：#{third_reservation.customer_name} #{third_reservation.party_size}人"
puts "   時間：#{third_reservation.reservation_datetime.strftime('%H:%M')}"
puts "   可用性：#{availability3[:has_availability] ? '✅ 可訂位' : '❌ 無法訂位'}"
puts "   分配結果：#{table3&.table_number || '無可用桌位'}"

if table3.nil? && availability3[:can_combine]
  puts "   併桌選項：#{availability3[:combinable_tables].map(&:table_number).join(', ')}"
end

puts
puts "=== 測試完成 ==="

# 清理測試資料
puts "🧹 清理測試資料..."
restaurant.reservations.where("customer_name LIKE ?", "測試客戶%").destroy_all
restaurant.reservations.where(customer_name: ["張先生", "王小姐", "李先生"]).destroy_all
puts "✅ 清理完成" 