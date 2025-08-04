# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

Rails.logger.debug '建立測試資料...'

# 創建超級管理員
super_admin = User.find_or_create_by(email: 'admin@example.com') do |user|
  user.first_name = '系統'
  user.last_name = '管理員'
  user.password = 'password'
  user.password_confirmation = 'password'
  user.role = 'super_admin'
  user.active = true
end

Rails.logger.debug { "超級管理員已創建: #{super_admin.email} (#{super_admin.role_display_name})" }

# 創建測試餐廳
restaurant = Restaurant.find_or_create_by(name: '測試餐廳') do |r|
  r.description = '這是一個測試餐廳，用於系統測試'
  r.phone = '02-1234-5678'
  r.address = '台北市信義區信義路五段7號'
  r.active = true
end

Rails.logger.debug { "測試餐廳已創建: #{restaurant.name}" }

# 創建餐廳管理員
restaurant_manager = User.find_or_create_by(email: 'manager@example.com') do |user|
  user.first_name = '餐廳'
  user.last_name = '管理員'
  user.password = 'password'
  user.password_confirmation = 'password'
  user.role = 'manager'
  user.restaurant = restaurant
  user.active = true
end

Rails.logger.debug { "餐廳管理員已創建: #{restaurant_manager.email} (#{restaurant_manager.role_display_name})" }

# 創建餐廳員工
restaurant_employee = User.find_or_create_by(email: 'employee@example.com') do |user|
  user.first_name = '餐廳'
  user.last_name = '員工'
  user.password = 'password'
  user.password_confirmation = 'password'
  user.role = 'employee'
  user.restaurant = restaurant
  user.active = true
end

Rails.logger.debug { "餐廳員工已創建: #{restaurant_employee.email} (#{restaurant_employee.role_display_name})" }

# 創建桌位群組
table_group = restaurant.table_groups.find_or_create_by(name: '大廳區') do |tg|
  tg.description = '餐廳主要用餐區域'
  tg.sort_order = 1
  tg.active = true
end

Rails.logger.debug { "桌位群組已創建: #{table_group.name}" }

# 創建一些測試桌位
(1..6).each do |i|
  table = table_group.restaurant_tables.find_or_create_by(table_number: "A#{i}") do |t|
    t.restaurant = restaurant
    t.capacity = [2, 4, 6].sample
    t.max_capacity = t.capacity + 2
    t.min_capacity = 1
    t.table_type = %w[regular round square].sample
    t.status = 'available'
    t.sort_order = i
    t.active = true
  end

  Rails.logger.debug { "桌位已創建: #{table.table_number} (#{table.capacity}人)" } if table.persisted?
end

# 建立營業時段 (Operating Hours)
# 先找到或建立餐廳
restaurant = Restaurant.find_or_create_by!(name: '測試餐廳')

# 定義每週的營業時間
# weekday: 0 (週日) to 6 (週六)
weekly_hours_data = [
  # 週一至週五 午餐
  { weekday: 1, open_time: '11:30', close_time: '14:30', sort_order: 1 },
  { weekday: 2, open_time: '11:30', close_time: '14:30', sort_order: 1 },
  { weekday: 3, open_time: '11:30', close_time: '14:30', sort_order: 1 },
  { weekday: 4, open_time: '11:30', close_time: '14:30', sort_order: 1 },
  { weekday: 5, open_time: '11:30', close_time: '14:30', sort_order: 1 },
  
  # 週一至週五 晚餐
  { weekday: 1, open_time: '17:30', close_time: '21:30', sort_order: 2 },
  { weekday: 2, open_time: '17:30', close_time: '21:30', sort_order: 2 },
  { weekday: 3, open_time: '17:30', close_time: '21:30', sort_order: 2 },
  { weekday: 4, open_time: '17:30', close_time: '21:30', sort_order: 2 },
  { weekday: 5, open_time: '17:30', close_time: '21:30', sort_order: 2 },

  # 週六、週日 全天
  { weekday: 6, open_time: '11:30', close_time: '21:30', sort_order: 1 },
  { weekday: 0, open_time: '11:30', close_time: '21:30', sort_order: 1 }
]

# 清空現有的營業時間以避免重複
restaurant.operating_hours.destroy_all

# 遍歷並創建 OperatingHour
weekly_hours_data.each do |hour_data|
  OperatingHour.create!(
    restaurant: restaurant,
    weekday: hour_data[:weekday],
    open_time: hour_data[:open_time],
    close_time: hour_data[:close_time],
    sort_order: hour_data[:sort_order]
  )
end

Rails.logger.debug { "為 #{restaurant.name} 創建了 #{weekly_hours_data.count} 個營業時段" }

# 建立預約政策
unless restaurant.reservation_policy
  restaurant.create_reservation_policy!(
    advance_booking_days: 30,
    minimum_advance_hours: 2,
    max_party_size: 8,
    min_party_size: 1,
    no_show_policy: '未到場的預約將被取消，並可能影響未來預約權限。',
    modification_policy: '可在用餐前2小時修改預約，超過時限請致電餐廳。',
    deposit_required: false,
    deposit_amount: 0.0,
    deposit_per_person: false
  )
  Rails.logger.debug '預約政策已創建'
end

Rails.logger.debug "\n種子資料創建完成！"
Rails.logger.debug "\n登入資訊："
Rails.logger.debug '超級管理員 - Email: admin@example.com, Password: password'
Rails.logger.debug '餐廳管理員 - Email: manager@example.com, Password: password'
Rails.logger.debug '餐廳員工   - Email: employee@example.com, Password: password'
