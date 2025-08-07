module WeeklyPeriodHelpers
  # 為餐廳創建完整的週間營業時段設定
  def create_full_week_periods(restaurant, options = {})
    # 預設的營業時段設定
    default_periods = {
      lunch: { start_time: '11:30', end_time: '14:00', name: '午餐' },
      dinner: { start_time: '17:30', end_time: '21:00', name: '晚餐' }
    }
    
    periods = options[:periods] || default_periods
    weekdays = options[:weekdays] || (0..6).to_a # 預設全週營業
    
    created_periods = []
    
    weekdays.each do |weekday|
      periods.each do |period_type, period_config|
        period = create(:reservation_period, 
          restaurant: restaurant,
          weekday: weekday,
          name: "#{period_config[:name]}(#{weekday_name(weekday)})",
          start_time: period_config[:start_time],
          end_time: period_config[:end_time],
          reservation_interval_minutes: period_config[:interval] || 30
        )
        created_periods << period
      end
    end
    
    created_periods
  end
  
  # 為餐廳創建工作日營業時段（週一到週五）
  def create_weekday_periods(restaurant, options = {})
    create_full_week_periods(restaurant, options.merge(weekdays: (1..5).to_a))
  end
  
  # 為餐廳創建週末營業時段
  def create_weekend_periods(restaurant, options = {})
    weekend_periods = {
      brunch: { start_time: '10:00', end_time: '15:00', name: '早午餐' },
      dinner: { start_time: '17:30', end_time: '22:00', name: '晚餐' }
    }
    
    periods = options[:periods] || weekend_periods
    create_full_week_periods(restaurant, options.merge(weekdays: [0, 6], periods: periods))
  end
  
  # 創建單一餐期的全週設定
  def create_single_period_full_week(restaurant, period_config)
    (0..6).map do |weekday|
      create(:reservation_period,
        restaurant: restaurant,
        weekday: weekday,
        name: "#{period_config[:name]}(#{weekday_name(weekday)})",
        start_time: period_config[:start_time],
        end_time: period_config[:end_time],
        reservation_interval_minutes: period_config[:interval] || 30
      )
    end
  end
  
  # 為指定日期創建全天營業的設定（用於測試）
  def create_all_day_periods(restaurant, weekdays = (0..6).to_a)
    weekdays.map do |weekday|
      create(:reservation_period,
        restaurant: restaurant,
        weekday: weekday,
        name: "全日營業(#{weekday_name(weekday)})",
        start_time: '09:00',
        end_time: '22:00',
        reservation_interval_minutes: 30
      )
    end
  end
  
  # 建立餐廳基本測試設定（包含桌位群組和桌位）
  def setup_restaurant_for_testing(restaurant)
    # 確保餐廳有基本的營業設定
    unless restaurant.reservation_periods.any?
      create_full_week_periods(restaurant)
    end

    # 確保餐廳有桌位群組和桌位
    unless restaurant.table_groups.any?
      table_group = restaurant.table_groups.create!(
        name: '主要區域',
        description: '主要用餐區域',
        active: true
      )

      # 創建不同容量的桌位進行測試
      restaurant.restaurant_tables.create!(
        table_number: 'A1',
        capacity: 2,
        min_capacity: 1,
        max_capacity: 2,
        table_type: 'regular',
        operational_status: 'normal',
        sort_order: 1,
        can_combine: true,
        table_group: table_group,
        active: true
      )
      
      restaurant.restaurant_tables.create!(
        table_number: 'A2',
        capacity: 4,
        min_capacity: 2,
        max_capacity: 4,
        table_type: 'regular',
        operational_status: 'normal',
        sort_order: 2,
        can_combine: true,
        table_group: table_group,
        active: true
      )

      restaurant.restaurant_tables.create!(
        table_number: 'A3',
        capacity: 6,
        min_capacity: 4,
        max_capacity: 6,
        table_type: 'regular',
        operational_status: 'normal',
        sort_order: 3,
        can_combine: true,
        table_group: table_group,
        active: true
      )

      # 確保餐廳總容量被正確計算和快取
      restaurant.update_cached_capacity
    end
    
    restaurant.reload
  end
  
  # 替代舊的 days_of_week 參數的輔助方法
  def weekdays_from_names(day_names)
    day_mapping = {
      'sunday' => 0, 'monday' => 1, 'tuesday' => 2, 'wednesday' => 3,
      'thursday' => 4, 'friday' => 5, 'saturday' => 6
    }
    
    day_names.map { |name| day_mapping[name.downcase] }.compact
  end
  
  # 將舊式的 days_of_week 陣列轉換為新的週間設定
  def create_periods_from_days_of_week(restaurant, days_of_week, period_config = {})
    weekdays = weekdays_from_names(days_of_week)
    
    default_config = {
      name: '營業時段',
      start_time: '11:30',
      end_time: '21:00',
      reservation_interval_minutes: 30
    }
    
    config = default_config.merge(period_config)
    
    weekdays.map do |weekday|
      create(:reservation_period,
        restaurant: restaurant,
        weekday: weekday,
        **config
      )
    end
  end

  private
  
  def weekday_name(weekday)
    %w[日 一 二 三 四 五 六][weekday]
  end
end

# 包含到 RSpec 配置中
RSpec.configure do |config|
  config.include WeeklyPeriodHelpers, type: :request
  config.include WeeklyPeriodHelpers, type: :service
  config.include WeeklyPeriodHelpers, type: :controller
end