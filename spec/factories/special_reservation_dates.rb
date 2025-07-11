FactoryBot.define do
  factory :special_reservation_date do
    restaurant
    sequence(:name) { |n| "特殊訂位日#{n}" }
    description { "特殊訂位日描述" }
    sequence(:start_date) { |n| Date.current + (n * 5).days }
    sequence(:end_date) { |n| Date.current + (n * 5 + 2).days }
    operation_mode { "closed" }
    active { true }

    trait :closed do
      operation_mode { "closed" }
    end

    trait :custom_hours do
      operation_mode { "custom_hours" }
      table_usage_minutes { 120 }
      custom_periods do
        [
          {
            start_time: "18:00",
            end_time: "20:00",
            interval_minutes: 120
          }
        ]
      end
    end

    trait :multi_period do
      operation_mode { "custom_hours" }
      table_usage_minutes { 90 }
      custom_periods do
        [
          {
            start_time: "18:00",
            end_time: "20:00",
            interval_minutes: 60
          },
          {
            start_time: "21:00",
            end_time: "23:00",
            interval_minutes: 60
          }
        ]
      end
    end

    trait :single_day do
      start_date { Date.current + 1.day }
      end_date { Date.current + 1.day }
    end

    trait :multi_day do
      start_date { Date.current + 1.day }
      end_date { Date.current + 3.days }
    end


    trait :weekend_special do
      name { "週末特殊營業" }
      start_date { Date.current.beginning_of_week + 5.days } # 這週六
      end_date { Date.current.beginning_of_week + 6.days }   # 這週日
      operation_mode { "custom_hours" }
      table_usage_minutes { 150 }
      custom_periods do
        [
          {
            start_time: "17:00",
            end_time: "21:00",
            interval_minutes: 120
          }
        ]
      end
    end

    trait :holiday_special do
      name { "假日特殊營業" }
      description { "假日特殊菜單，限時供應" }
      start_date { Date.current + 7.days }
      end_date { Date.current + 7.days }
      operation_mode { "custom_hours" }
      table_usage_minutes { 180 }
      custom_periods do
        [
          {
            start_time: "17:30",
            end_time: "21:30",
            interval_minutes: 120
          }
        ]
      end
    end

    trait :new_year_special do
      name { "新年特殊營業" }
      description { "新年特殊菜單，僅限預約" }
      start_date { Date.current + 30.days }
      end_date { Date.current + 32.days }
      operation_mode { "custom_hours" }
      table_usage_minutes { 240 }
      custom_periods do
        [
          {
            start_time: "18:00",
            end_time: "22:00",
            interval_minutes: 240
          }
        ]
      end
    end

    trait :inactive do
      active { false }
    end
  end
end