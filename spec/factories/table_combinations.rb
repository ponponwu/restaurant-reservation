FactoryBot.define do
  factory :table_combination do
    association :reservation
    name { '併桌組合' }
    notes { '併桌備註' }

    # 簡化版本：不自動創建桌位，避免複雜的依賴問題
    trait :without_tables do
      # 預設版本：不自動創建桌位
      # 這避免了批次執行時的複雜依賴問題
    end

    trait :with_default_tables do
      # 只在明確需要時才創建桌位
      after(:create) do |combination|
        restaurant = combination.reservation.restaurant
        table_group = restaurant.table_groups.first || create(:table_group, restaurant: restaurant)
        
        # 使用批次安全的創建方法
        table1 = create(:table, 
          restaurant: restaurant, 
          table_group: table_group, 
          can_combine: true, 
          table_number: "C#{combination.id}-1"
        )
        table2 = create(:table, 
          restaurant: restaurant, 
          table_group: table_group, 
          can_combine: true, 
          table_number: "C#{combination.id}-2"
        )
        
        combination.restaurant_tables = [table1, table2]
        combination.save!
      end
    end

    trait :with_specific_tables do |tables|
      # 用於測試中需要特定桌位的情況
      after(:build) do |combination, evaluator|
        if evaluator.respond_to?(:tables) && evaluator.tables
          combination.restaurant_tables = evaluator.tables
        end
      end
    end
  end
end
