module ComplexScenariosHelper
  # 建立標準的餐廳設定，包含多種桌位類型
  def create_standard_restaurant_setup
    restaurant = create(:restaurant, name: '標準測試餐廳')
    business_period = create(:business_period, restaurant: restaurant)
    
    # 建立桌位群組
    square_group = create(:table_group, name: '方桌', restaurant: restaurant, priority: 1)
    round_group = create(:table_group, name: '圓桌', restaurant: restaurant, priority: 2)
    window_group = create(:table_group, name: '窗邊', restaurant: restaurant, priority: 3)
    bar_group = create(:table_group, name: '吧台', restaurant: restaurant, priority: 5)
    
    # 建立不同類型的桌位
    tables = {}
    
    # 2人方桌 x 4
    tables[:square_2] = 4.times.map do |i|
      create(:table, 
             restaurant: restaurant,
             table_group: square_group,
             table_number: "S2-#{i+1}",
             table_type: 'square',
             min_capacity: 1,
             max_capacity: 2,
             operational_status: 'normal')
    end
    
    # 4人方桌 x 4  
    tables[:square_4] = 4.times.map do |i|
      create(:table,
             restaurant: restaurant,
             table_group: square_group,
             table_number: "S4-#{i+1}",
             table_type: 'square',
             min_capacity: 2,
             max_capacity: 4,
             operational_status: 'normal')
    end
    
    # 6人圓桌 x 3
    tables[:round_6] = 3.times.map do |i|
      create(:table,
             restaurant: restaurant,
             table_group: round_group,
             table_number: "R6-#{i+1}",
             table_type: 'round',
             min_capacity: 4,
             max_capacity: 6,
             operational_status: 'normal')
    end
    
    # 窗邊圓桌 x 2（8人桌，可併桌）
    tables[:window_8] = 2.times.map do |i|
      create(:table,
             restaurant: restaurant,
             table_group: window_group,
             table_number: "W8-#{i+1}",
             table_type: 'round',
             min_capacity: 6,
             max_capacity: 8,
             operational_status: 'normal',
             is_child_friendly: true,
             has_high_chair: true)
    end
    
    # 吧台座位 x 6（1-2人）
    tables[:bar_seats] = 6.times.map do |i|
      create(:table,
             restaurant: restaurant,
             table_group: bar_group,
             table_number: "B-#{i+1}",
             table_type: 'bar',
             min_capacity: 1,
             max_capacity: 2,
             operational_status: 'normal',
             is_child_friendly: false)
    end
    
    {
      restaurant: restaurant,
      business_period: business_period,
      tables: tables,
      groups: {
        square: square_group,
        round: round_group,
        window: window_group,
        bar: bar_group
      }
    }
  end

  # 建立壓力測試情境
  def create_stress_test_scenario(restaurant, business_period, target_time, fill_percentage = 0.8)
    all_tables = restaurant.restaurant_tables.active.where(operational_status: 'normal')
    tables_to_fill = (all_tables.count * fill_percentage).round
    
    all_tables.limit(tables_to_fill).each_with_index do |table, index|
      create(:reservation, :confirmed,
             restaurant: restaurant,
             business_period: business_period,
             table: table,
             customer_name: "壓力測試客戶#{index + 1}",
             customer_phone: "0900#{(1000 + index).to_s}",
             party_size: [table.min_capacity, table.max_capacity].compact.min,
             adults_count: [table.min_capacity, table.max_capacity].compact.min,
             children_count: 0,
             reservation_datetime: target_time)
    end
    
    {
      filled_tables: tables_to_fill,
      available_tables: all_tables.count - tables_to_fill,
      total_tables: all_tables.count
    }
  end

  # 建立時間衝突測試情境
  def create_time_conflict_scenario(restaurant, business_period, base_time)
    conflicts = []
    
    # 情境1：重疊用餐時間
    table1 = restaurant.restaurant_tables.active.first
    reservation1 = create(:reservation, :confirmed,
                         restaurant: restaurant,
                         business_period: business_period,
                         table: table1,
                         customer_name: '先到客戶',
                         reservation_datetime: base_time,
                         party_size: 2)
    
    # 嘗試在1小時後預約同一桌（應該衝突）
    conflicting_reservation = build(:reservation,
                                   restaurant: restaurant,
                                   business_period: business_period,
                                   table: table1,
                                   customer_name: '衝突客戶',
                                   reservation_datetime: base_time + 1.hour,
                                   party_size: 2)
    
    conflicts << {
      existing: reservation1,
      conflicting: conflicting_reservation,
      should_conflict: true
    }
    
    # 情境2：緩衝時間後的預約（不應該衝突）
    non_conflicting_reservation = build(:reservation,
                                       restaurant: restaurant,
                                       business_period: business_period,
                                       table: table1,
                                       customer_name: '安全時間客戶',
                                       reservation_datetime: base_time + 3.hours,
                                       party_size: 2)
    
    conflicts << {
      existing: reservation1,
      conflicting: non_conflicting_reservation,
      should_conflict: false
    }
    
    conflicts
  end

  # 建立併桌測試情境
  def create_table_combination_scenario(restaurant, business_period, party_size)
    # 確保有足夠的桌位可以併桌
    suitable_tables = restaurant.restaurant_tables
                               .active
                               .where(operational_status: 'normal')
                               .where('max_capacity >= ?', [party_size / 3, 2].max)
                               .limit(4)
    
    return nil if suitable_tables.count < 2
    
    # 建立併桌的訂位
    large_reservation = create(:reservation,
                              restaurant: restaurant,
                              business_period: business_period,
                              customer_name: "大聚會客戶",
                              customer_phone: "0988888888",
                              party_size: party_size,
                              adults_count: party_size - [party_size / 4, 0].max,
                              children_count: [party_size / 4, 0].max,
                              reservation_datetime: 1.day.from_now.change(hour: 18, min: 0))
    
    {
      reservation: large_reservation,
      available_tables: suitable_tables,
      required_capacity: party_size
    }
  end

  # 建立特殊需求測試情境
  def create_special_needs_scenarios(restaurant, business_period, base_time)
    scenarios = []
    
    # 情境1：有兒童的家庭
    family_reservation = build(:reservation,
                              restaurant: restaurant,
                              business_period: business_period,
                              customer_name: '家庭客戶',
                              party_size: 4,
                              adults_count: 2,
                              children_count: 2,
                              special_requests: '需要兒童座椅',
                              reservation_datetime: base_time)
    
    scenarios << {
      type: :family_with_children,
      reservation: family_reservation,
      requirements: [:child_friendly, :no_bar_tables, :high_chair]
    }
    
    # 情境2：無障礙需求
    accessible_reservation = build(:reservation,
                                  restaurant: restaurant,
                                  business_period: business_period,
                                  customer_name: '無障礙客戶',
                                  party_size: 2,
                                  adults_count: 2,
                                  children_count: 0,
                                  special_requests: '需要輪椅無障礙桌位',
                                  reservation_datetime: base_time + 1.hour)
    
    scenarios << {
      type: :wheelchair_accessible,
      reservation: accessible_reservation,
      requirements: [:wheelchair_accessible, :ground_floor, :wide_space]
    }
    
    # 情境3：商務聚餐
    business_reservation = build(:reservation,
                                restaurant: restaurant,
                                business_period: business_period,
                                customer_name: '商務客戶',
                                party_size: 6,
                                adults_count: 6,
                                children_count: 0,
                                special_requests: '需要安靜環境，商務聚餐',
                                reservation_datetime: base_time + 2.hours)
    
    scenarios << {
      type: :business_meeting,
      reservation: business_reservation,
      requirements: [:quiet_area, :round_table_preferred, :good_lighting]
    }
    
    scenarios
  end

  # 驗證桌位分配結果
  def validate_allocation_result(reservation, allocated_table, requirements = [])
    validation_results = {
      table_assigned: allocated_table.present?,
      capacity_suitable: false,
      requirements_met: {},
      overall_valid: false
    }
    
    if allocated_table
      # 檢查容量是否合適
      validation_results[:capacity_suitable] = allocated_table.suitable_for?(reservation.party_size)
      
      # 檢查特殊需求
      requirements.each do |requirement|
        case requirement
        when :child_friendly
          validation_results[:requirements_met][:child_friendly] = 
            reservation.children_count > 0 ? allocated_table.is_child_friendly : true
        when :no_bar_tables
          validation_results[:requirements_met][:no_bar_tables] = 
            reservation.children_count > 0 ? allocated_table.table_type != 'bar' : true
        end
      end
      
      # 計算整體有效性
      requirements_valid = validation_results[:requirements_met].values.all?(true)
      validation_results[:overall_valid] = validation_results[:capacity_suitable] && requirements_valid
    end
    
    validation_results
  end

  # 計算分配成功率
  def calculate_allocation_success_rate(attempts, successful_allocations)
    return 0.0 if attempts == 0
    (successful_allocations.to_f / attempts * 100).round(2)
  end

  # 生成測試報告
  def generate_test_report(test_name, results)
    report = {
      test_name: test_name,
      timestamp: Time.current,
      summary: results[:summary] || {},
      details: results[:details] || [],
      performance: results[:performance] || {},
      recommendations: results[:recommendations] || []
    }
    
    # 可選：將報告寫入檔案
    if ENV['GENERATE_TEST_REPORTS'] == 'true'
      report_path = Rails.root.join('tmp', 'test_reports', "#{test_name}_#{Time.current.to_i}.json")
      FileUtils.mkdir_p(File.dirname(report_path))
      File.write(report_path, JSON.pretty_generate(report))
    end
    
    report
  end

  # 清理測試資料
  def cleanup_test_data(restaurant_id = nil)
    if restaurant_id
      Reservation.where(restaurant_id: restaurant_id).delete_all
      TableCombination.where(restaurant_id: restaurant_id).delete_all
      RestaurantTable.where(restaurant_id: restaurant_id).delete_all
      TableGroup.where(restaurant_id: restaurant_id).delete_all
    else
      # 僅清理測試相關的資料
      Reservation.where("customer_name LIKE ? OR customer_name LIKE ?", '%測試%', '%客戶%').delete_all
      TableCombination.joins(:restaurant).where("restaurants.name LIKE ?", '%測試%').delete_all
    end
  end
end

# 在RSpec中包含這個helper
RSpec.configure do |config|
  config.include ComplexScenariosHelper, type: :model
  config.include ComplexScenariosHelper, type: :service  
  config.include ComplexScenariosHelper, type: :system
  config.include ComplexScenariosHelper, type: :request
end 