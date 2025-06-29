FactoryBot.define do
  factory :table_combination do
    association :reservation
    name { '併桌組合' }
    notes { '併桌備註' }

    # 使用 after(:build) 而不是 after(:create) 來在驗證前建立關聯
    after(:build) do |combination|
      if combination.restaurant_tables.empty?
        restaurant = combination.reservation.restaurant
        table_group = create(:table_group, restaurant: restaurant)
        table1 = create(:table, restaurant: restaurant, table_group: table_group, can_combine: true)
        table2 = create(:table, restaurant: restaurant, table_group: table_group, can_combine: true)
        combination.restaurant_tables = [table1, table2]
      end
    end

    trait :without_tables do
      # 用於需要手動控制桌位的驗證測試
      after(:build) do |combination|
        # 清空預設桌位，允許手動控制
        combination.restaurant_tables = []
      end
    end
  end
end
