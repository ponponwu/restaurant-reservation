#!/usr/bin/env ruby
# 管理員介面桌位分配測試腳本

require_relative 'config/environment'

puts "🎯 管理員介面桌位分配測試"
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

test_time = 2.hours.from_now
puts "🕐 測試時間: #{test_time.strftime('%Y-%m-%d %H:%M')}"

class AdminReservationTestService
  def initialize(restaurant, business_period)
    @restaurant = restaurant
    @business_period = business_period
  end

  def create_reservation_with_allocation(params)
    # 模擬控制器的行為
    reservation = Reservation.new(params.merge(
      restaurant: @restaurant,
      business_period: @business_period,
      status: :pending
    ))

    if reservation.valid?
      # 模擬控制器的 allocate_table_for_reservation 方法
      allocator = ReservationAllocatorService.new(reservation)
      allocated_table = allocator.allocate_table
      
      if allocated_table
        if allocated_table.is_a?(Array)
          # 併桌情況 - 創建 TableCombination
          combination = TableCombination.new(
            reservation: reservation,
            name: "併桌 #{allocated_table.map(&:table_number).join('+')}"
          )
          
          # 建立桌位關聯
          allocated_table.each do |table|
            combination.table_combination_tables.build(restaurant_table: table)
          end
          
          if reservation.save && combination.save
            puts "  ✅ 併桌分配成功: #{allocated_table.map(&:table_number).join(', ')}"
            return { success: true, reservation: reservation, type: :combination, tables: allocated_table }
          else
            puts "  ❌ 併桌組合保存失敗: #{combination.errors.full_messages.join(', ')}"
            return { success: false, errors: combination.errors.full_messages }
          end
        else
          # 單桌情況
          reservation.table = allocated_table
          if reservation.save
            puts "  ✅ 單桌分配成功: #{allocated_table.table_number}"
            return { success: true, reservation: reservation, type: :single, table: allocated_table }
          else
            puts "  ❌ 訂位保存失敗: #{reservation.errors.full_messages.join(', ')}"
            return { success: false, errors: reservation.errors.full_messages }
          end
        end
      else
        puts "  ⚠️  無法分配桌位"
        return { success: false, errors: ['無可用桌位'] }
      end
    else
      puts "  ❌ 訂位驗證失敗: #{reservation.errors.full_messages.join(', ')}"
      return { success: false, errors: reservation.errors.full_messages }
    end
  end
end

# 建立測試服務
service = AdminReservationTestService.new(restaurant, business_period)
successful_reservations = []

puts "\n🧪 連續建立訂位測試"
puts "-" * 30

5.times do |i|
  puts "\n#{i+1}. 建立訂位 #{i+1} (客戶#{i+1}, 2人)"
  
  params = {
    customer_name: "客戶#{i+1}",
    customer_phone: "091234567#{i}",
    customer_email: "customer#{i}@example.com",
    party_size: 2,
    adults_count: 2,
    children_count: 0,
    reservation_datetime: test_time
  }
  
  # 顯示當前桌位狀況
  puts "  🔍 當前桌位狀況："
  restaurant.restaurant_tables.active.ordered.each do |table|
    conflicts = table.find_conflicting_reservations(test_time, 120)
    status = conflicts.any? ? "🔴 佔用" : "🟢 可用"
    puts "     #{table.table_number}: #{status}"
    if conflicts.any?
      conflicts.each do |res|
        combination_info = res.table_combination ? " (併桌)" : ""
        puts "       └── #{res.customer_name}#{combination_info}"
      end
    end
  end
  
  result = service.create_reservation_with_allocation(params)
  
  if result[:success]
    successful_reservations << result[:reservation]
    puts "  📝 訂位 ID: #{result[:reservation].id}"
  end
end

puts "\n🔍 重複分配檢查"
puts "-" * 30

# 檢查單桌重複分配
single_table_reservations = successful_reservations.select { |r| r.table_id.present? }
table_usage = {}

single_table_reservations.each do |reservation|
  table_id = reservation.table_id
  table_usage[table_id] ||= []
  table_usage[table_id] << reservation
end

duplicates_found = false
table_usage.each do |table_id, reservations|
  if reservations.count > 1
    table = RestaurantTable.find(table_id)
    puts "❌ 桌位 #{table.table_number} 被重複分配給:"
    reservations.each do |r|
      puts "   - #{r.customer_name} (ID: #{r.id})"
    end
    duplicates_found = true
  end
end

# 檢查併桌重複分配
combination_reservations = successful_reservations.select { |r| r.table_combination.present? }
combination_table_usage = {}

combination_reservations.each do |reservation|
  combination = reservation.table_combination
  combination.restaurant_tables.each do |table|
    combination_table_usage[table.id] ||= []
    combination_table_usage[table.id] << reservation
  end
end

combination_table_usage.each do |table_id, reservations|
  if reservations.count > 1
    table = RestaurantTable.find(table_id)
    puts "❌ 桌位 #{table.table_number} 在併桌中被重複使用:"
    reservations.each do |r|
      combination_info = r.table_combination.restaurant_tables.map(&:table_number).join(', ')
      puts "   - #{r.customer_name} (併桌: #{combination_info})"
    end
    duplicates_found = true
  end
end

# 檢查單桌和併桌之間的衝突
all_used_table_ids = table_usage.keys + combination_table_usage.keys
cross_conflicts = all_used_table_ids.group_by(&:itself).select { |_, v| v.size > 1 }

cross_conflicts.each do |table_id, _|
  single_users = table_usage[table_id] || []
  combination_users = combination_table_usage[table_id] || []
  
  if single_users.any? && combination_users.any?
    table = RestaurantTable.find(table_id)
    puts "❌ 桌位 #{table.table_number} 同時被單桌和併桌使用:"
    single_users.each { |r| puts "   - 單桌: #{r.customer_name}" }
    combination_users.each { |r| puts "   - 併桌: #{r.customer_name}" }
    duplicates_found = true
  end
end

if !duplicates_found
  puts "✅ 沒有發現重複分配問題"
end

puts "\n🧹 清理測試資料"
puts "-" * 30

successful_reservations.each do |reservation|
  puts "刪除訂位: #{reservation.customer_name} (ID: #{reservation.id})"
  reservation.table_combination&.destroy
  reservation.destroy
end

puts "\n✅ 測試完成" 