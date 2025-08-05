module ModelTestHelpers
  # 創建乾淨的餐廳實例，適用於隔離測試
  def create_clean_restaurant(overrides = {})
    # 使用正常的創建過程，但確保參數唯一性
    unique_suffix = SecureRandom.hex(4)
    defaults = {
      name: "Restaurant #{unique_suffix}",
      phone: "0912#{unique_suffix[0..5]}"
    }
    
    restaurant = create(:restaurant, defaults.merge(overrides))
    
    # 確保基本的 reservation_policy 存在
    restaurant.create_reservation_policy unless restaurant.reservation_policy
    
    restaurant.reload
  end

  # 創建乾淨的桌位組合，避免 factory 複雜性
  def create_clean_table_combination(restaurant: nil, table_count: 2, **options)
    restaurant ||= create_clean_restaurant
    
    # 創建預約
    reservation = create(:reservation, restaurant: restaurant)
    
    # 手動創建桌位組合，避免 factory 複雜性
    combination = build(:table_combination, :without_tables, 
      reservation: reservation,
      name: options[:name] || '測試併桌'
    )
    
    if table_count > 0
      # 創建桌位群組
      table_group = create(:table_group, restaurant: restaurant)
      
      # 使用隨機數確保桌號唯一性
      unique_suffix = SecureRandom.hex(3)
      
      # 創建指定數量的桌位
      tables = table_count.times.map do |i|
        create(:table, 
          restaurant: restaurant, 
          table_group: table_group,
          table_number: "T#{unique_suffix}-#{i + 1}",
          can_combine: true,
          capacity: 4,
          max_capacity: 4
        )
      end
      combination.restaurant_tables = tables
    end
    
    combination.save!(validate: false) # 跳過驗證以避免批次執行問題
    
    combination
  end

  # 為驗證測試創建最小化的測試對象
  def build_clean_subject_for_validation(factory_name, **attributes)
    case factory_name
    when :table_combination
      restaurant = create_clean_restaurant
      table_group = create(:table_group, restaurant: restaurant)
      reservation = create(:reservation, restaurant: restaurant)
      
      build(:table_combination, :without_tables, 
        reservation: reservation, 
        **attributes
      )
    else
      build(factory_name, **attributes)
    end
  end

  # 重置測試環境的輔助方法
  def reset_factory_sequences
    FactoryBot.factories.each do |factory|
      factory.defined_traits.each do |trait|
        trait.definition.callbacks.clear if trait.definition.respond_to?(:callbacks)
      end
    end
  end

  # 測試數據隔離檢查
  def ensure_clean_database
    expect(Restaurant.count).to eq(0), "Database not clean: #{Restaurant.count} restaurants found"
    expect(Reservation.count).to eq(0), "Database not clean: #{Reservation.count} reservations found"
    expect(TableCombination.count).to eq(0), "Database not clean: #{TableCombination.count} combinations found"
  end

  # 批次執行安全的創建方法，支援 traits
  def create_batch_safe(factory_name, *args)
    # 解析參數：traits 和 attributes
    traits = []
    attributes = {}
    
    args.each do |arg|
      if arg.is_a?(Hash)
        attributes = arg
      else
        traits << arg
      end
    end
    
    # 為批次執行添加隨機性以避免衝突
    unique_number = rand(1000..9999)
    
    case factory_name
    when :restaurant
      attributes[:name] ||= "Rest #{unique_number}"
      attributes[:phone] ||= "0912#{unique_number}"
    when :table
      attributes[:table_number] ||= "T#{unique_number}"
    when :reservation
      attributes[:customer_phone] ||= "0912#{unique_number}"
    end
    
    # 使用 traits 和 attributes 創建
    if traits.any?
      create(factory_name, *traits, attributes)
    else
      create(factory_name, attributes)
    end
  end
end

RSpec.configure do |config|
  config.include ModelTestHelpers, type: :model
end