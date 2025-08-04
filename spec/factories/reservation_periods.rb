FactoryBot.define do
  factory :reservation_period do
    restaurant
    name { '午餐時段' }
    start_time { '12:00' }
    end_time { '14:00' }
    weekday { 1 } # 預設星期一
    reservation_interval_minutes { 30 }
    active { true }

    # 每日特性
    trait :sunday do
      name { '週日營業' }
      weekday { 0 }
    end

    trait :monday do
      name { '週一營業' }
      weekday { 1 }
    end

    trait :tuesday do
      name { '週二營業' }
      weekday { 2 }
    end

    trait :wednesday do
      name { '週三營業' }
      weekday { 3 }
    end

    trait :thursday do
      name { '週四營業' }
      weekday { 4 }
    end

    trait :friday do
      name { '週五營業' }
      weekday { 5 }
    end

    trait :saturday do
      name { '週六營業' }
      weekday { 6 }
    end

    # 營業模式特性
    trait :weekend do
      name { '週末早午餐' }
      start_time { '10:00' }
      end_time { '15:00' }
      weekday { 6 }
    end

    trait :dinner do
      name { '晚餐時段' }
      start_time { '18:00' }
      end_time { '22:00' }
    end

    trait :twenty_four_hours do
      name { '24小時營業' }
      start_time { '00:00' }
      end_time { '23:59' }
      reservation_interval_minutes { 60 }
    end

    trait :closed do
      name { '不開放' }
      active { false }
    end

    trait :specific_date do
      date { Date.current + 1.day }
    end

    trait :fifteen_minute_interval do
      reservation_interval_minutes { 15 }
    end

    trait :sixty_minute_interval do
      reservation_interval_minutes { 60 }
    end

    trait :inactive do
      active { false }
    end
  end
end
