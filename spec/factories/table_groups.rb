FactoryBot.define do
  factory :table_group do
    association :restaurant
    name { '主要用餐區' }
    description { '餐廳主要用餐區域' }
    sort_order { 1 }
    active { true }
  end
end
