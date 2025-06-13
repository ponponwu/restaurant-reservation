FactoryBot.define do
  factory :blacklist do
    association :restaurant
    association :added_by, factory: :user
    customer_name { Faker::Name.name }
    customer_phone { "09#{rand(10000000..99999999)}" }
    reason { Faker::Lorem.sentence }
    active { true }
  end
end
