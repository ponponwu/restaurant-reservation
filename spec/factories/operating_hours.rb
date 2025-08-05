FactoryBot.define do
  factory :operating_hour do
    restaurant
    weekday { 1 }
    open_time { Time.parse('09:00') }
    close_time { Time.parse('17:00') }
    sort_order { 1 }

    trait :monday do
      weekday { 1 }
    end

    trait :tuesday do
      weekday { 2 }
    end

    trait :lunch_hours do
      open_time { Time.parse('11:30') }
      close_time { Time.parse('14:30') }
    end

    trait :dinner_hours do
      open_time { Time.parse('17:30') }
      close_time { Time.parse('21:30') }
    end
  end
end
