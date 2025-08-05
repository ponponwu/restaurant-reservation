FactoryBot.define do
  factory :table_combination_table do
    # 使用簡化的依賴創建
    after(:build) do |tct|
      # 創建有桌位的 table_combination
      if tct.table_combination.nil?
        tct.table_combination = FactoryBot.create(:table_combination, :with_default_tables)
      end
      
      # 使用 combination 中的第一個桌位
      if tct.restaurant_table.nil?
        tct.restaurant_table = tct.table_combination.restaurant_tables.first
      end
    end
    
    trait :with_specific_table do
      # 用於需要特定桌位的測試
    end
  end
end