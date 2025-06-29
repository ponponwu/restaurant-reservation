FactoryBot.define do
  factory :restaurant do
    sequence(:name) { |n| "Restaurant #{n}" }
    description { 'A wonderful dining experience' }
    phone { '123-456-7890' }
    address { '123 Main Street, City, State 12345' }
    reservation_interval_minutes { 30 }
    active { true }
    deleted_at { nil }

    # 自動創建 reservation_policy
    after(:create) do |restaurant|
      restaurant.create_reservation_policy unless restaurant.reservation_policy
    end

    trait :inactive do
      active { false }
    end

    trait :deleted do
      deleted_at { Time.current }
    end

    trait :with_15_min_intervals do
      reservation_interval_minutes { 15 }
    end

    trait :with_60_min_intervals do
      reservation_interval_minutes { 60 }
    end

    trait :with_business_periods do
      after(:create) do |restaurant|
        # 創建基本的午餐和晚餐時段
        restaurant.business_periods.create!(
          name: '午餐',
          start_time: '11:30',
          end_time: '14:30',
          days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday],
          active: true,
          status: 'active'
        )
        
        restaurant.business_periods.create!(
          name: '晚餐',
          start_time: '17:30',
          end_time: '21:30',
          days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday],
          active: true,
          status: 'active'
        )
      end
    end

    trait :with_tables do
      after(:create) do |restaurant|
        # 創建基本的table group
        table_group = restaurant.table_groups.create!(
          name: '主要用餐區',
          description: '主要用餐區域',
          sort_order: 1,
          active: true
        )
        
        # 創建一些餐桌
        restaurant.restaurant_tables.create!(
          table_number: 'A1',
          capacity: 2,
          max_capacity: 4,
          table_type: 'regular',
          operational_status: 'normal',
          active: true,
          can_combine: true,
          table_group: table_group,
          sort_order: 1
        )
        
        restaurant.restaurant_tables.create!(
          table_number: 'A2',
          capacity: 4,
          max_capacity: 6,
          table_type: 'regular',
          operational_status: 'normal',
          active: true,
          can_combine: true,
          table_group: table_group,
          sort_order: 2
        )
        
        restaurant.restaurant_tables.create!(
          table_number: 'A3',
          capacity: 6,
          max_capacity: 8,
          table_type: 'regular',
          operational_status: 'normal',
          active: true,
          can_combine: true,
          table_group: table_group,
          sort_order: 3
        )
      end
    end
  end
end
