#!/usr/bin/env ruby

puts '最終修復 PostgreSQL SQL 語法問題...'

puts '修復中...'

file_path = 'app/services/reservation_allocator_service.rb'
content = File.read(file_path)

# 完全替換 get_reserved_table_ids 方法
old_method = /  def get_reserved_table_ids\(datetime\).*?^  end/m

new_method = <<~RUBY
  def get_reserved_table_ids(datetime)
    return [] unless datetime

    reserved_table_ids = []

    # 如果是無限時模式，檢查同一餐期的衝突（每餐期每桌只有一個訂位）
    if @restaurant.policy.unlimited_dining_time?
      return [] unless @business_period_id # 如果沒有餐期ID，不檢查衝突

      target_date = datetime.to_date
      business_period = ReservationPeriod.find(@business_period_id)

      conflicting_reservations = Reservation.where(restaurant: @restaurant)
        .where(status: %w[pending confirmed])
        .where('DATE(reservation_datetime) = ?', target_date)
        .where(business_period: business_period)
        .includes(:table, table_combination: :restaurant_tables)
    else
      # 使用餐廳設定的用餐時間
      duration_minutes = @restaurant.dining_duration_with_buffer
      return [] unless duration_minutes # 如果沒有設定時間，不檢查衝突

      # 計算新訂位的時間範圍
      new_start_time = datetime
      new_end_time = datetime + duration_minutes.minutes
  #{'    '}
      # 先查詢可能重疊的預訂，然後在 Ruby 中計算時間重疊
      potential_conflicts = Reservation.where(restaurant: @restaurant)
        .where(status: %w[pending confirmed])
        .where("reservation_datetime BETWEEN ? AND ?", new_start_time - duration_minutes.minutes, new_end_time)
        .includes(:table, table_combination: :restaurant_tables)
  #{'    '}
      # 在 Ruby 中過濾真正重疊的預訂
      conflicting_reservations = potential_conflicts.select do |reservation|
        existing_start = reservation.reservation_datetime
        existing_end = existing_start + duration_minutes.minutes
  #{'      '}
        # 檢查時間重疊：existing_start < new_end AND new_start < existing_end
        existing_start < new_end_time && new_start_time < existing_end
      end
    end

    # 收集所有被佔用的桌位
    conflicting_reservations.each do |reservation|
      # 收集單一桌位
      reserved_table_ids << reservation.table_id if reservation.table_id.present?

      # 收集併桌中的所有桌位
      if reservation.table_combination.present?
        combination_table_ids = reservation.table_combination.restaurant_tables.pluck(:id)
        reserved_table_ids.concat(combination_table_ids)
      end
    end

    reserved_table_ids.uniq.compact
  end
RUBY

content.gsub!(old_method, new_method)

# 直接替換有問題的 SQL 行
content.gsub!('"reservation_datetime < ? AND (reservation_datetime + INTERVAL ? MINUTE) > ?",',
              '"reservation_datetime BETWEEN ? AND ?",')

# 替換參數順序
content.gsub!(
  'new_start_time - duration_minutes.minutes, new_end_time',
  'new_start_time - duration_minutes.minutes, new_end_time'
)

# 替換整個查詢邏輯
content.gsub!(
  /      # 查詢與此時間範圍重疊的預訂\n      # 兩個時間區間重疊的條件：existing_start < new_end AND new_start < existing_end\n      conflicting_reservations = Reservation\.where\(restaurant: @restaurant\)\n        \.where\(status: %w\[pending confirmed\]\)\n        \.where\(\n          "reservation_datetime BETWEEN \? AND \?",\n          new_start_time - duration_minutes\.minutes, new_end_time\n        \)\n        \.includes\(:table, table_combination: :restaurant_tables\)/,
  '      # 先查詢可能重疊的預訂，然後在 Ruby 中計算時間重疊
      potential_conflicts = Reservation.where(restaurant: @restaurant)
        .where(status: %w[pending confirmed])
        .where("reservation_datetime BETWEEN ? AND ?", new_start_time - duration_minutes.minutes, new_end_time)
        .includes(:table, table_combination: :restaurant_tables)

      # 在 Ruby 中過濾真正重疊的預訂
      conflicting_reservations = potential_conflicts.select do |reservation|
        existing_start = reservation.reservation_datetime
        existing_end = existing_start + duration_minutes.minutes

        # 檢查時間重疊：existing_start < new_end AND new_start < existing_end
        existing_start < new_end_time && new_start_time < existing_end
      end'
)

File.write(file_path, content)

puts '✅ 最終修復完成！'

puts 'OK'
