FactoryBot.define do
  factory :blacklist do
    association :restaurant
    customer_name { Faker::Name.name }
    customer_phone { "09#{rand(10000000..99999999)}" }
    reason { Faker::Lorem.sentence }
    added_by_name { Faker::Name.name }
    active { true }
  end
end
