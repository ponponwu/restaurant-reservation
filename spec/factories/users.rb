FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { 'password123' }
    password_confirmation { 'password123' }
    first_name { '測試' }
    last_name { '使用者' }
    password_changed_at { 1.day.ago }

    trait :admin do
      first_name { '系統' }
      last_name { '管理員' }
      sequence(:email) { |n| "admin#{n}@example.com" }
      role { :super_admin }
    end

    trait :manager do
      first_name { '餐廳' }
      last_name { '經理' }
      sequence(:email) { |n| "manager#{n}@example.com" }
      role { :manager }
    end
  end
end
