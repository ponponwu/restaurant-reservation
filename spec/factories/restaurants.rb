FactoryBot.define do
  factory :restaurant do
    sequence(:name) { |n| "Restaurant #{n}" }
    description { "A wonderful dining experience" }
    phone { "123-456-7890" }
    address { "123 Main Street, City, State 12345" }
    reservation_interval_minutes { 30 }
    active { true }
    deleted_at { nil }
    
    # 自動創建 reservation_policy
    after(:create) do |restaurant|
      restaurant.create_reservation_policy unless restaurant.reservation_policy
    end
    
    trait :inactive do
      active { false }
    end
    
    trait :deleted do
      deleted_at { Time.current }
    end
    
    trait :with_15_min_intervals do
      reservation_interval_minutes { 15 }
    end
    
    trait :with_60_min_intervals do
      reservation_interval_minutes { 60 }
    end
  end
end
