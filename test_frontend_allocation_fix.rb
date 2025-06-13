#!/usr/bin/env ruby
# 測試前台桌位分配修正

require_relative 'config/environment'

puts "🔧 測試前台桌位分配修正"
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
restaurant.reservations.where("customer_name LIKE ?", "前台測試%").destroy_all

test_time = 2.hours.from_now
puts "\n🕒 測試時間: #{test_time.strftime('%Y/%m/%d %H:%M')}"

# 模擬前台控制器的邏輯
puts "\n🧪 模擬前台訂位流程"
puts "-" * 30

def simulate_frontend_reservation(restaurant, business_period, test_time, customer_name, party_size = 4)
  puts "創建訂位: #{customer_name} (#{party_size}人)"
  
  reservation = Reservation.new(
    restaurant: restaurant,
    business_period: business_period,
    customer_name: customer_name,
    customer_phone: "0912345#{rand(100..999)}",
    customer_email: "test#{rand(100..999)}@example.com",
    party_size: party_size,
    adults_count: party_size,
    children_count: 0,
    reservation_datetime: test_time,
    status: :confirmed
  )
  
  success = false
  allocated_info = nil
  
  ActiveRecord::Base.transaction do
    # 使用桌位分配服務來分配桌位
    allocator = ReservationAllocatorService.new({
      restaurant: restaurant,
      party_size: reservation.party_size,
      adults: reservation.adults_count,
      children: reservation.children_count,
      reservation_datetime: reservation.reservation_datetime,
      business_period_id: business_period.id
    })
    
    # 檢查是否有可用桌位
    allocated_table = allocator.allocate_table
    
    if allocated_table.nil?
      puts "  ❌ 沒有可用桌位"
      return { success: false, error: "沒有可用桌位" }
    end
    
    # 處理桌位分配
    if allocated_table.is_a?(Array)
      # 併桌情況
      combination = TableCombination.new(
        reservation: reservation,
        name: "併桌 #{allocated_table.map(&:table_number).join('+')}"
      )
      
      allocated_table.each do |table|
        combination.table_combination_tables.build(restaurant_table: table)
      end
      
      reservation.table = allocated_table.first
      
      if reservation.save && combination.save
        allocated_info = "併桌: #{allocated_table.map(&:table_number).join(', ')}"
        success = true
      else
        puts "  ❌ 併桌訂位保存失敗: 訂位錯誤: #{reservation.errors.full_messages.join(', ')}, 併桌錯誤: #{combination.errors.full_messages.join(', ')}"
        raise ActiveRecord::Rollback
      end
    else
      # 單一桌位
      reservation.table = allocated_table
      
      if reservation.save
        allocated_info = "單桌: #{allocated_table.table_number}"
        success = true
      else
        puts "  ❌ 單桌訂位保存失敗: #{reservation.errors.full_messages.join(', ')}"
        raise ActiveRecord::Rollback
      end
    end
  end
  
  if success
    puts "  ✅ 訂位成功 (ID: #{reservation.id})"
    puts "     分配: #{allocated_info}"
    { success: true, reservation: reservation, allocation: allocated_info }
  else
    { success: false, error: "保存失敗" }
  end
end

# 測試多次訂位
results = []
customers = ["前台測試客戶1", "前台測試客戶2", "前台測試客戶3"]

customers.each_with_index do |customer, index|
  puts "\n#{index + 1}. 測試客戶: #{customer}"
  result = simulate_frontend_reservation(restaurant, business_period, test_time, customer)
  results << result if result[:success]
end

# 檢查結果
puts "\n📊 測試結果統計"
puts "-" * 30

successful_reservations = results.select { |r| r[:success] }
puts "成功訂位數: #{successful_reservations.count}"

if successful_reservations.any?
  puts "\n成功的訂位："
  successful_reservations.each_with_index do |result, index|
    res = result[:reservation]
    puts "#{index + 1}. #{res.customer_name}"
    puts "   ID: #{res.id}"
    puts "   分配: #{result[:allocation]}"
    puts "   時間: #{res.reservation_datetime.strftime('%Y/%m/%d %H:%M')}"
    puts "   狀態: #{res.status}"
  end
end

# 檢查桌位衝突
puts "\n🔍 桌位衝突檢查"
puts "-" * 30

test_reservations = restaurant.reservations.where("customer_name LIKE ?", "前台測試%")
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

# 最終清理
puts "\n🧹 清理所有測試資料"
restaurant.reservations.where("customer_name LIKE ?", "%測試%").destroy_all
puts "測試完成" 