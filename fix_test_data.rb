#!/usr/bin/env ruby
require_relative 'config/environment'

puts "=== 修正測試資料 ==="
puts

# 找到測試餐廳
restaurant = Restaurant.first
if restaurant.nil?
  puts "❌ 找不到測試餐廳"
  exit 1
end

puts "🏪 修正餐廳：#{restaurant.name}"

# 1. 啟用併桌功能
restaurant.update!(
  allow_table_combinations: true,
  max_combination_tables: 3,
  buffer_time_minutes: 15
)
puts "✅ 已啟用併桌功能"

# 2. 設定桌位支援併桌（除了窗邊圓桌）
restaurant.restaurant_tables.each do |table|
  if table.table_number.include?('窗邊')
    table.update!(can_combine: false)
    puts "   #{table.table_number}：保持不可併桌（特殊桌位）"
  else
    table.update!(can_combine: true)
    puts "   #{table.table_number}：設定為可併桌"
  end
end

# 3. 檢查營業時段
business_period = restaurant.business_periods.active.first
if business_period.nil?
  # 建立預設營業時段
  business_period = restaurant.business_periods.create!(
    name: '晚餐時段',
    start_time: '17:00',
    end_time: '22:00',
    days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday],
    status: 'active'
  )
  puts "✅ 已建立預設營業時段：#{business_period.name}"
else
  puts "✅ 營業時段已存在：#{business_period.name}"
end

# 4. 顯示修正後的狀態
puts
puts "📊 修正後狀態："
puts "   允許併桌：#{restaurant.can_combine_tables? ? '✅ 是' : '❌ 否'}"
puts "   可併桌桌位：#{restaurant.restaurant_tables.where(can_combine: true).count} 張"
puts "   營業時段：#{restaurant.business_periods.active.count} 個"

puts
puts "=== 修正完成 ===" 