#!/usr/bin/env ruby
require_relative 'config/environment'

restaurant = Restaurant.find_by(name: "Maan")

puts "Restaurant total_capacity: #{restaurant.total_capacity}"
puts "Restaurant responds to total_capacity: #{restaurant.respond_to?(:total_capacity)}"

# 檢查現有桌位的 sort_order
puts "Current tables sort_order:"
restaurant.restaurant_tables.active.order(:sort_order).each do |table|
  puts "- #{table.table_number}: sort_order=#{table.sort_order}, suitable_for(4)=#{table.suitable_for?(4)}"
end

# 創建測試桌位
restaurant.restaurant_tables.where(table_number: ['T4', 'T2', 'O1']).destroy_all
restaurant.table_groups.where(name: ['測試群組', '其他群組']).destroy_all

test_group = restaurant.table_groups.create!(name: '測試群組', sort_order: 0)
table_4_person = restaurant.restaurant_tables.create!(
  table_number: 'T4',
  capacity: 4,
  min_capacity: 2,
  max_capacity: 6,
  table_type: 'square',
  sort_order: 0,
  can_combine: true,
  operational_status: 'normal',
  active: true,
  table_group: test_group
)

puts "Created T4 table with id: #{table_4_person.id}"

# 檢查 ordered scope 的結果
puts "\nOrdered tables:"
restaurant.restaurant_tables.active.ordered.each do |table|
  puts "- #{table.table_number} (id: #{table.id}, sort_order: #{table.sort_order}, group_sort: #{table.table_group&.sort_order})"
end

# 測試分配器
business_period = restaurant.business_periods.active.first
allocator = ReservationAllocatorService.new({
  restaurant: restaurant,
  party_size: 4,
  adults: 4,
  children: 0,
  reservation_datetime: 2.hours.from_now,
  business_period_id: business_period.id
})

puts "\nTesting capacity check:"
exceeds = allocator.send(:exceeds_restaurant_capacity?)
puts "Exceeds capacity: #{exceeds}"

puts "\nTesting find_suitable_table:"
suitable = allocator.send(:find_suitable_table)
puts "Suitable table: #{suitable&.table_number || 'nil'}"

puts "\nTesting allocate_table step by step:"
party_size = allocator.send(:total_party_size)
puts "Party size: #{party_size}"
puts "Party size < 1: #{party_size < 1}"
puts "Exceeds capacity: #{exceeds}"

if !exceeds
  table = allocator.send(:find_suitable_table)
  puts "Found suitable table: #{table&.table_number || 'nil'}"
  
  if table
    puts "Should return table: #{table.table_number}"
  else
    puts "No suitable table found, checking combinable tables..."
    can_combine = restaurant.can_combine_tables?
    puts "Can combine tables: #{can_combine}"
    
    if can_combine
      combinable = allocator.find_combinable_tables
      puts "Combinable tables: #{combinable&.map(&:table_number) || 'nil'}"
    end
  end
end 