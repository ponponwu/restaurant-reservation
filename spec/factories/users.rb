FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    name { "測試使用者" }
    phone { "0912345678" }
    
    trait :admin do
      name { "管理員" }
      email { "admin@example.com" }
    end
    
    trait :manager do
      name { "經理" }
      email { "manager@example.com" }
    end
  end
end
