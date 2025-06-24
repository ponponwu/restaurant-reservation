require 'set'

namespace :reservation_bot do
  desc '測試用訂位機器人 - 將指定餐廳的指定日期範圍內的所有時段訂滿'
  task :fill_reservations, [:restaurant_slug, :start_date, :end_date, :party_size] => :environment do |_task, args|
    puts '🤖 啟動訂位機器人...'

    # 驗證參數
    unless args.restaurant_slug.present?
      puts '❌ 請提供餐廳 slug'
      puts '使用方式: rails reservation_bot:fill_reservations[restaurant-slug,2025-01-01,2025-01-31,2]'
      exit 1
    end

    # 查找餐廳
    restaurant = Restaurant.find_by(slug: args.restaurant_slug)
    unless restaurant
      puts "❌ 找不到餐廳: #{args.restaurant_slug}"
      exit 1
    end

    puts "🏪 目標餐廳: #{restaurant.name}"

    # 解析日期參數
    begin
      start_date = args.start_date.present? ? Date.parse(args.start_date) : Date.current
      end_date = args.end_date.present? ? Date.parse(args.end_date) : start_date + 7.days
      party_size = args.party_size.present? ? args.party_size.to_i : 2
    rescue ArgumentError => e
      puts "❌ 日期格式錯誤: #{e.message}"
      puts '請使用 YYYY-MM-DD 格式，例如: 2025-01-01'
      exit 1
    end

    # 驗證日期範圍
    if start_date < Date.current
      puts '❌ 開始日期不能是過去的日期'
      exit 1
    end

    if end_date < start_date
      puts '❌ 結束日期不能早於開始日期'
      exit 1
    end

    if (end_date - start_date).to_i > 90
      puts '❌ 日期範圍不能超過 90 天'
      exit 1
    end

    # 驗證人數
    policy = restaurant.reservation_policy
    min_party_size = policy&.min_party_size || 1
    max_party_size = policy&.max_party_size || 12

    if party_size < min_party_size || party_size > max_party_size
      puts "❌ 人數必須在 #{min_party_size}-#{max_party_size} 人之間"
      exit 1
    end

    puts "📅 日期範圍: #{start_date} 到 #{end_date}"
    puts "👥 預訂人數: #{party_size} 人"
    puts "📊 共 #{(end_date - start_date).to_i + 1} 天"

    # 確認執行
    puts "\n⚠️  這個操作將會在指定的日期範圍內建立大量測試訂位資料"
    puts "⚠️  建議只在開發環境使用"
    print "是否繼續？(y/N): "
    
    unless STDIN.gets.chomp.downcase == 'y'
      puts "❌ 操作已取消"
      exit 0
    end

    # 執行訂位機器人
    total_created = 0
    total_failed = 0
    failed_dates = []

    availability_service = AvailabilityService.new(restaurant)

    puts "\n🚀 開始建立訂位..."

    (start_date..end_date).each_with_index do |date, index|
      puts "\n📅 處理日期: #{date} (#{index + 1}/#{(end_date - start_date).to_i + 1})"

      # 檢查餐廳是否營業
      unless restaurant.open_on_date?(date)
        puts "   ⏸️  餐廳當天不營業，跳過"
        next
      end

      # 獲取當天所有可用時間選項
      available_time_options = restaurant.available_time_options_for_date(date)
      if available_time_options.empty?
        puts "   ⏸️  沒有可用時間選項，跳過"
        next
      end

      puts "   🕐 找到 #{available_time_options.size} 個時間選項"

      # 為當天建立訂位
      date_created = 0
      date_failed = 0

      available_time_options.each do |time_option|
        datetime = time_option[:datetime]
        business_period_id = time_option[:business_period_id]

        # 跳過過去的時間
        if datetime < Time.current
          next
        end

        # 策略性填滿桌位：優先使用大桌位，然後中桌位，最後單人桌
        tables_filled = fill_tables_strategically(restaurant, datetime, business_period_id, date)

        if tables_filled > 0
          puts "     ✅ #{time_option[:time]} - 成功建立 #{tables_filled} 筆訂位並分配桌位"
          date_created += tables_filled
          total_created += tables_filled
        else
          puts "     ⏸️  #{time_option[:time]} - 已無可用桌位"
        end

        # 添加小延遲避免過度負載
        sleep(0.05)
      end

      if date_failed > 0
        failed_dates << { date: date, failed_count: date_failed }
      end

      puts "   📊 當天結果: #{date_created} 成功, #{date_failed} 失敗"
    end

    # 總結報告
    puts "\n" + "="*50
    puts "🎯 訂位機器人執行完成"
    puts "📊 總結報告:"
    puts "   ✅ 成功建立: #{total_created} 筆訂位"
    puts "   ❌ 建立失敗: #{total_failed} 筆"
    
    if failed_dates.any?
      puts "\n⚠️  有失敗記錄的日期:"
      failed_dates.each do |item|
        puts "   #{item[:date]}: #{item[:failed_count]} 筆失敗"
      end
    end

    if total_created > 0
      puts "\n🧹 清理訂位資料:"
      puts "   可使用以下指令清理測試資料:"
      puts "   rails reservation_bot:cleanup_test_reservations[#{restaurant.slug}]"
    end

    puts "\n✨ 完成！"
  end

  desc '清理測試訂位資料'
  task :cleanup_test_reservations, [:restaurant_slug] => :environment do |_task, args|
    puts '🧹 清理測試訂位資料...'

    unless args.restaurant_slug.present?
      puts '❌ 請提供餐廳 slug'
      puts '使用方式: rails reservation_bot:cleanup_test_reservations[restaurant-slug]'
      exit 1
    end

    restaurant = Restaurant.find_by(slug: args.restaurant_slug)
    unless restaurant
      puts "❌ 找不到餐廳: #{args.restaurant_slug}"
      exit 1
    end

    puts "🏪 目標餐廳: #{restaurant.name}"

    # 查找測試訂位資料
    test_reservations = restaurant.reservations
      .where(special_requests: '機器人測試訂位')
      .where('reservation_datetime >= ?', Date.current)

    if test_reservations.empty?
      puts "📝 沒有找到測試訂位資料"
      exit 0
    end

    puts "📊 找到 #{test_reservations.count} 筆測試訂位資料"
    
    # 確認刪除
    print "是否確定要刪除這些測試資料？(y/N): "
    unless STDIN.gets.chomp.downcase == 'y'
      puts "❌ 操作已取消"
      exit 0
    end

    # 執行刪除
    deleted_count = 0
    test_reservations.find_each do |reservation|
      begin
        reservation.destroy!
        deleted_count += 1
        print "."
      rescue StandardError => e
        puts "\n❌ 刪除訂位 ##{reservation.id} 失敗: #{e.message}"
      end
    end

    puts "\n✅ 成功刪除 #{deleted_count} 筆測試訂位資料"
    puts "🧹 清理完成！"
  end

  desc '顯示訂位機器人使用說明'
  task :help => :environment do
    puts <<~HELP
      🤖 訂位機器人使用說明
      
      主要功能：
      ========
      
      1. 填滿指定餐廳的訂位時段
         rails reservation_bot:fill_reservations[restaurant-slug,start-date,end-date,party-size]
         
         參數說明：
         - restaurant-slug: 餐廳的 slug (必填)
         - start-date: 開始日期，格式 YYYY-MM-DD (選填，預設今天)
         - end-date: 結束日期，格式 YYYY-MM-DD (選填，預設開始日期+7天)
         - party-size: 預訂人數 (選填，預設2人)
         
         範例：
         rails reservation_bot:fill_reservations[my-restaurant,2025-07-01,2025-07-20,4]
         rails reservation_bot:fill_reservations[my-restaurant]  # 使用預設值
      
      2. 清理測試訂位資料
         rails reservation_bot:cleanup_test_reservations[restaurant-slug]
         
         範例：
         rails reservation_bot:cleanup_test_reservations[my-restaurant]
      
      3. 顯示此說明
         rails reservation_bot:help
      
      注意事項：
      ========
      - 建議只在開發環境使用
      - 機器人會跳過已過去的時間
      - 建立的測試訂位會標記為「機器人測試訂位」
      - 可以使用 cleanup 指令清理測試資料
      - 日期範圍限制最多 90 天
    HELP
  end

  private

  # 策略性填滿桌位：按容量從大到小分配
  def fill_tables_strategically(restaurant, datetime, business_period_id, date)
    created_count = 0

    # 獲取該確切時間點已有的訂位
    existing_reservations = restaurant.reservations
      .where(status: %w[pending confirmed])
      .where(reservation_datetime: datetime)
      .includes(:table, table_combination: :restaurant_tables)

    # 獲取已被佔用的桌位ID
    occupied_table_ids = Set.new
    existing_reservations.each do |reservation|
      if reservation.table_combination.present?
        reservation.table_combination.restaurant_tables.each { |t| occupied_table_ids.add(t.id) }
      elsif reservation.table.present?
        occupied_table_ids.add(reservation.table.id)
      end
    end

    # 獲取可用桌位，按容量從大到小排序
    available_tables = restaurant.restaurant_tables
      .active
      .available_for_booking
      .where.not(id: occupied_table_ids.to_a)
      .order(capacity: :desc)

    puts "       🔍 找到 #{available_tables.count} 張可用桌位"

    # 策略性分配桌位
    available_tables.each do |table|
      break if available_tables.where.not(id: occupied_table_ids.to_a).empty?

      # 跳過已被佔用的桌位
      next if occupied_table_ids.include?(table.id)

      # 根據桌位容量決定訂位人數
      optimal_party_size = determine_optimal_party_size(table.capacity)

      # 建立訂位
      reservation_data = {
        restaurant: restaurant,
        table: table,
        customer_name: generate_fake_name,
        customer_phone: generate_fake_phone,
        customer_email: generate_fake_email,
        party_size: optimal_party_size,
        adults_count: optimal_party_size,
        children_count: 0,
        reservation_datetime: datetime,
        business_period_id: business_period_id,
        status: 'confirmed',
        special_requests: '機器人測試訂位',
        skip_blacklist_validation: true,
        admin_override: false # 設為正常訂位，不是管理員強制建立
      }

      begin
        reservation = Reservation.create!(reservation_data)
        puts "       ✅ 桌位 #{table.table_number} (容量#{table.capacity}) - #{optimal_party_size}人訂位 (##{reservation.id})"
        created_count += 1
        occupied_table_ids.add(table.id)
      rescue StandardError => e
        puts "       ❌ 桌位 #{table.table_number} - 建立失敗: #{e.message}"
      end
    end

    created_count
  end

  # 根據桌位容量決定最佳訂位人數
  def determine_optimal_party_size(table_capacity)
    case table_capacity
    when 1
      1
    when 2
      [1, 2].sample # 隨機選擇1或2人
    when 4
      [2, 3, 4].sample # 隨機選擇2-4人
    when 6
      [4, 5, 6].sample # 隨機選擇4-6人
    when 8
      [6, 7, 8].sample # 隨機選擇6-8人
    else
      [table_capacity - 1, table_capacity].sample # 對於其他容量，選擇接近最大值
    end
  end

  # 生成假的姓名
  def generate_fake_name
    first_names = %w[王小明 李小華 張小美 陳小強 林小雅 黃小傑 劉小君 郭小豪 何小玲 吳小偉]
    surnames = %w[測試 機器人 假資料 範例 Demo Test Bot Sample Fake Mock]
    
    "#{surnames.sample}#{first_names.sample}"
  end

  # 生成假的電話號碼
  def generate_fake_phone
    # 生成台灣手機號碼格式 09xxxxxxxx
    "09#{rand(10000000..99999999)}"
  end

  # 生成假的電子郵件
  def generate_fake_email
    domains = %w[test.com example.com fake.mail bot.test]
    username = "testbot#{rand(1000..9999)}"
    
    "#{username}@#{domains.sample}"
  end
end