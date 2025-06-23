# 簡化版不限時用餐桌位分配系統

## 概述

本文件說明餐廳訂位系統中簡化版不限時用餐的桌位分配邏輯。此版本移除了複雜的權重計算，採用更直觀的分配策略。

## 核心原則

### 1. 每餐期每桌唯一性

-   在不限時用餐模式下，每個餐期（business_period）的每張桌位只能有一個訂位
-   不會有後續訂位的概念，因為客人可以無限時用餐

### 2. 簡單排序機制

-   不使用複雜的權重計算系統
-   直接使用桌位的 `sort_order` 進行排序
-   選擇第一個符合容量需求的桌位

### 3. 統一模式運作

-   不限時模式通常會統一使用，不會混合限時和不限時
-   避免複雜的衝突檢查邏輯

### 4. 同群組併桌限制

-   併桌只能在同一個桌位群組（table_group）內進行
-   不允許跨群組併桌，確保桌位的合理性

## 技術實作

### 桌位分配邏輯

```ruby
def find_suitable_table
  party_size = total_party_size
  suitable_tables = available_tables.select { |table| table.suitable_for?(party_size) }

  return nil if suitable_tables.empty?

  # 簡化：直接按 sort_order 排序，選擇第一個適合的桌位
  suitable_tables.first
end
```

### 餐期預訂檢查

```ruby
def check_table_booking_in_period(table, target_datetime)
  target_date = target_datetime.to_date
  business_period = BusinessPeriod.find(@business_period_id)

  # 查找該桌位在同一餐期的預訂
  existing_booking = Reservation.where(restaurant: @restaurant)
                               .where(status: 'confirmed')
                               .where('DATE(reservation_datetime) = ?', target_date)
                               .where(business_period: business_period)
                               .where(
                                 '(table_id = ?) OR (id IN (SELECT reservation_id FROM table_combinations tc JOIN table_combination_tables tct ON tc.id = tct.table_combination_id WHERE tct.restaurant_table_id = ?))',
                                 table.id, table.id
                               )
                               .first

  {
    has_booking: existing_booking.present?,
    existing_booking: existing_booking
  }
end
```

### 同群組併桌

```ruby
def find_combinable_tables
  return nil unless can_combine_tables?

  party_size = total_party_size
  combinable_tables = available_tables.select { |table| can_table_combine?(table) }

  return nil if combinable_tables.empty?

  # 只在同群組內尋找組合
  tables_by_group = combinable_tables.group_by(&:table_group_id)

  tables_by_group.each do |group_id, group_tables|
    combination = find_best_combination_in_group(group_tables, party_size)
    return combination if combination
  end

  # 不允許跨群組併桌
  nil
end
```

### 併桌組合邏輯

```ruby
def find_best_combination_in_group(group_tables, party_size)
  # 簡化：按 sort_order 排序，嘗試最少桌位的組合
  sorted_tables = group_tables.sort_by(&:sort_order)

  max_tables = @restaurant.max_tables_per_combination

  # 嘗試不同的組合大小（從2桌開始到最大允許桌數）
  (2..max_tables).each do |combination_size|
    sorted_tables.combination(combination_size) do |table_combination|
      total_capacity = table_combination.sum(&:capacity)

      # 檢查容量是否足夠
      next unless total_capacity >= party_size

      # 檢查是否所有桌位都可以併桌
      next unless table_combination.all? { |table| can_table_combine?(table) }

      # 不限時模式下，檢查同餐期是否有衝突
      if @restaurant.policy.unlimited_dining_time?
        has_conflict = table_combination.any? do |table|
          booking_check = check_table_booking_in_period(table, @reservation_datetime)
          booking_check[:has_booking]
        end
        next if has_conflict
      end

      return table_combination
    end
  end

  nil
end
```

## 使用方式

### 基本桌位分配

```ruby
# 初始化分配器
allocator = ReservationAllocatorService.new({
  restaurant: restaurant,
  party_size: 4,
  adults: 4,
  children: 0,
  reservation_datetime: DateTime.current + 2.hours,
  business_period_id: business_period.id
})

# 分配桌位
table = allocator.allocate_table

if table.is_a?(Array)
  # 併桌情況
  puts "分配併桌: #{table.map(&:table_number).join(', ')}"
elsif table
  # 單桌情況
  puts "分配單桌: #{table.table_number}"
else
  puts "無可用桌位"
end
```

### 檢查可用性

```ruby
availability = allocator.check_availability

puts "有可用桌位: #{availability[:has_availability]}"
puts "可用桌位數: #{availability[:available_tables].count}"
puts "可併桌: #{availability[:can_combine]}"
puts "併桌選項數: #{availability[:combinable_tables].count}"
```

### 檢查特定桌位在餐期的預訂狀況

```ruby
table = restaurant.restaurant_tables.find_by(table_number: 'A1')
booking_check = allocator.check_table_booking_in_period(table, DateTime.current + 2.hours)

puts "該桌位已被預訂: #{booking_check[:has_booking]}"
if booking_check[:has_booking]
  existing = booking_check[:existing_booking]
  puts "現有預訂: #{existing.customer_name} (#{existing.party_size}人)"
end
```

## 配置要求

### 餐廳政策設定

```ruby
# 啟用不限時用餐
restaurant.reservation_policy.update!(unlimited_dining_time: true)
```

### 桌位設定

```ruby
# 桌位必須設定 sort_order 以確保正確排序
table.update!(sort_order: 10)

# 併桌桌位必須設定 can_combine 為 true
table.update!(can_combine: true)
```

### 桌位群組設定

```ruby
# 桌位必須分配到適當的群組
table.update!(table_group: table_group)
```

## 測試

執行測試腳本來驗證功能：

```bash
ruby test_unlimited_dining_allocation.rb
```

測試涵蓋：

-   每餐期每桌唯一性驗證
-   sort_order 排序機制
-   同群組併桌限制
-   不同餐期桌位重用
-   可用性檢查 API

## 限制與注意事項

1. **餐期隔離**：不同餐期的預訂完全獨立，不會互相影響
2. **群組限制**：併桌嚴格限制在同一群組內，不允許跨群組
3. **排序依賴**：桌位分配完全依賴 sort_order，需要正確設定
4. **容量檢查**：仍會檢查餐廳總容量限制
5. **狀態限制**：只檢查 'confirmed' 狀態的預訂

## 與限時模式的差異

| 特性     | 不限時模式 | 限時模式       |
| -------- | ---------- | -------------- |
| 預訂檢查 | 按餐期檢查 | 按時間區間檢查 |
| 桌位分配 | 簡單排序   | 複雜權重計算   |
| 併桌限制 | 同群組內   | 可跨群組       |
| 衝突處理 | 餐期唯一性 | 時間重疊檢查   |
| 容量計算 | 餐期總容量 | 時段容量       |

這個簡化版本提供了更直觀和可預測的桌位分配邏輯，特別適合不限時用餐的場景。
