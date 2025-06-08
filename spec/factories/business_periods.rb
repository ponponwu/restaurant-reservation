FactoryBot.define do
  factory :business_period do
    association :restaurant
    name { "午餐時段" }
    start_time { "12:00" }
    end_time { "14:00" }
    days_of_week { %w[monday tuesday wednesday thursday friday] }
    active { true }
    
    trait :weekend do
      name { "週末早午餐" }
      start_time { "10:00" }
      end_time { "15:00" }
      days_of_week { %w[saturday sunday] }
    end
    
    trait :dinner do
      name { "晚餐時段" }
      start_time { "18:00" }
      end_time { "22:00" }
      days_of_week { %w[monday tuesday wednesday thursday friday saturday sunday] }
    end
    
    trait :inactive do
      active { false }
    end
  end
end
