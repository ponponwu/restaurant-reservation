FactoryBot.define do
  factory :reservation do
    restaurant
    business_period

    sequence(:customer_name) { |n| "顧客#{n}" }
    sequence(:customer_phone) { |n| "0912#{format('%06d', n)}" }
    sequence(:customer_email) { |n| "customer#{n}@example.com" }

    party_size { 2 }
    adults_count { 2 }
    children_count { 0 }
    reservation_datetime { 1.day.from_now.change(hour: 12, min: 0) }
    status { 'pending' }
    special_requests { '' }
    notes { '' }

    trait :with_table do
      table
    end

    trait :confirmed do
      status { 'confirmed' }
    end

    trait :cancelled do
      status { 'cancelled' }
    end

    trait :large_party do
      party_size { 8 }
      adults_count { 6 }
      children_count { 2 }
    end

    trait :single_person do
      party_size { 1 }
      adults_count { 1 }
      children_count { 0 }
    end

    trait :with_children do
      party_size { 4 }
      adults_count { 2 }
      children_count { 2 }
    end

    trait :future_datetime do
      reservation_datetime { 2.days.from_now.change(hour: 18, min: 0) }
    end
  end
end
