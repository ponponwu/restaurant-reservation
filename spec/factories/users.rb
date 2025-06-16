FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    first_name { "測試" }
    last_name { "使用者" }
    
    trait :admin do
      first_name { "系統" }
      last_name { "管理員" }
      email { "admin@example.com" }
      role { :super_admin }
    end
    
    trait :manager do
      first_name { "餐廳" }
      last_name { "經理" }
      email { "manager@example.com" }
      role { :manager }
    end
  end
end
