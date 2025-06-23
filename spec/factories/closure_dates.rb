FactoryBot.define do
  factory :closure_date do
    restaurant { association :restaurant }
    date { 1.week.from_now.to_date }
    reason { '公休日' }
    all_day { true }

    trait :today do
      date { Date.current }
    end

    trait :tomorrow do
      date { Date.tomorrow }
    end

    trait :partial_closure do
      all_day { false }
      start_time { '14:30' }
      end_time { '17:00' }
      reason { '設備維護' }
    end

    trait :recurring_weekly do
      recurring { true }
      weekday { 1 } # Monday
      reason { '每週固定公休' }
    end

    trait :national_holiday do
      reason { '國定假期' }
      all_day { true }
    end
  end
end
