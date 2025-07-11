FactoryBot.define do
  factory :table_group do
    restaurant
    sequence(:name) { |n| "用餐區#{n}" }
    description { '餐廳主要用餐區域' }
    sort_order { 1 }
    active { true }
  end
end
