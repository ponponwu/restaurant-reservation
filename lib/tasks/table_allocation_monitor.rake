namespace :table_allocation do
  desc '檢測桌位重複分配問題'
  task detect_duplicates: :environment do
    puts '正在檢測桌位重複分配...'

    duplicates = TableAllocationMonitorService.detect_duplicate_allocations

    if duplicates.empty?
      puts '✅ 未發現桌位重複分配問題'
    else
      puts "⚠️  發現 #{duplicates.size} 個桌位重複分配問題："

      duplicates.each_with_index do |duplicate, index|
        puts "\n問題 #{index + 1}:"
        puts "  桌位 ID: #{duplicate[:table_id]}"
        puts "  衝突類型: #{duplicate[:conflict_type]}"
        puts '  涉及預訂:'
        duplicate[:reservations].each do |res|
          puts "    - 預訂 #{res.id}: #{res.customer_name} 於 #{res.reservation_datetime}"
        end
        puts "  重疊時間: #{duplicate[:overlap_period][:duration_minutes]} 分鐘"
      end

      puts "\n使用 'rake table_allocation:fix_duplicates' 來自動修復這些問題"
    end
  end

  desc '修復檢測到的桌位重複分配'
  task fix_duplicates: :environment do
    puts '正在檢測並修復桌位重複分配...'

    duplicates = TableAllocationMonitorService.detect_duplicate_allocations

    if duplicates.empty?
      puts '✅ 未發現需要修復的問題'
      next
    end

    puts "發現 #{duplicates.size} 個重複分配問題，正在修復..."

    fixed_count = TableAllocationMonitorService.fix_duplicate_allocations(duplicates)

    puts "✅ 成功修復 #{fixed_count} 個重複分配問題"

    # 再次檢測確認修復結果
    remaining_duplicates = TableAllocationMonitorService.detect_duplicate_allocations
    if remaining_duplicates.empty?
      puts '✅ 所有問題已修復'
    else
      puts "⚠️  仍有 #{remaining_duplicates.size} 個問題需要手動處理"
    end
  end

  desc '監控指定餐廳的桌位分配'
  task :monitor_restaurant, [:restaurant_id] => :environment do |_t, args|
    restaurant_id = args[:restaurant_id]&.to_i

    if restaurant_id.nil?
      puts '請指定餐廳 ID: rake table_allocation:monitor_restaurant[123]'
      next
    end

    restaurant = Restaurant.find_by(id: restaurant_id)
    unless restaurant
      puts "找不到 ID 為 #{restaurant_id} 的餐廳"
      next
    end

    puts "正在監控餐廳: #{restaurant.name} (ID: #{restaurant_id})"

    duplicates = TableAllocationMonitorService.check_and_log_duplicates(restaurant_id)

    if duplicates.empty?
      puts "✅ 餐廳 #{restaurant.name} 沒有桌位重複分配問題"
    else
      puts "⚠️  餐廳 #{restaurant.name} 發現 #{duplicates.size} 個桌位重複分配問題"
      puts '詳細信息已記錄到日誌中'
    end
  end

  desc '生成桌位分配監控報告'
  task generate_report: :environment do
    puts '正在生成桌位分配監控報告...'

    total_restaurants = Restaurant.active.count
    total_reservations = Reservation.where(status: %w[confirmed pending]).count

    puts "\n=== 桌位分配監控報告 ==="
    puts "生成時間: #{Time.current}"
    puts "活躍餐廳數: #{total_restaurants}"
    puts "活躍預訂數: #{total_reservations}"

    # 按餐廳檢測問題
    problem_restaurants = []

    Restaurant.active.find_each do |restaurant|
      duplicates = TableAllocationMonitorService.detect_duplicate_allocations(restaurant.id)

      if duplicates.any?
        problem_restaurants << {
          restaurant: restaurant,
          duplicate_count: duplicates.size,
          duplicates: duplicates
        }
      end
    end

    if problem_restaurants.empty?
      puts '✅ 所有餐廳都沒有桌位重複分配問題'
    else
      puts "\n⚠️  發現問題的餐廳:"
      problem_restaurants.each do |info|
        puts "  #{info[:restaurant].name} (ID: #{info[:restaurant].id}): #{info[:duplicate_count]} 個問題"
      end

      puts "\n詳細問題:"
      problem_restaurants.each do |info|
        puts "\n餐廳: #{info[:restaurant].name}"
        info[:duplicates].each_with_index do |duplicate, index|
          puts "  問題 #{index + 1}: 桌位 #{duplicate[:table_id]}, #{duplicate[:reservations].size} 個衝突預訂"
        end
      end
    end

    puts "\n=== 報告結束 ==="
  end

  desc '設置桌位分配監控定時任務'
  task setup_monitoring: :environment do
    puts '設置桌位分配監控...'

    # 這裡可以設置定時任務（如 cron job 或 whenever gem）
    puts '建議在 crontab 中添加以下任務：'
    puts '# 每小時檢測桌位重複分配'
    puts "0 * * * * cd #{Rails.root} && bundle exec rake table_allocation:detect_duplicates RAILS_ENV=#{Rails.env}"
    puts ''
    puts '# 每日生成監控報告'
    puts "0 6 * * * cd #{Rails.root} && bundle exec rake table_allocation:generate_report RAILS_ENV=#{Rails.env}"

    puts "\n或者在 config/schedule.rb 中添加 whenever 任務"
  end
end
