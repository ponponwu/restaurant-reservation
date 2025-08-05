FactoryBot.define do
  factory :restaurant do
    sequence(:name) { |n| "Restaurant #{n}" }
    description { 'A wonderful dining experience' }
    phone { '123-456-7890' }
    address { '123 Main Street, City, State 12345' }
    reservation_interval_minutes { 30 }
    active { true }
    deleted_at { nil }

    # 只創建基本的 reservation_policy，不自動創建桌位
    after(:create) do |restaurant|
      # 自動創建 reservation_policy
      restaurant.create_reservation_policy unless restaurant.reservation_policy
    end

    trait :inactive do
      active { false }
    end

    trait :with_basic_tables do
      after(:create) do |restaurant|
        # 創建基本的table group和桌位
        table_group = restaurant.table_groups.create!(
          name: '主要用餐區',
          description: '主要用餐區域',
          sort_order: 1,
          active: true
        )

        # 創建幾張基本餐桌
        restaurant.restaurant_tables.create!(
          table_number: 'T1',
          capacity: 4,
          max_capacity: 4,
          table_type: 'regular',
          operational_status: 'normal',
          active: true,
          can_combine: true,
          table_group: table_group,
          sort_order: 1
        )

        restaurant.restaurant_tables.create!(
          table_number: 'T2',
          capacity: 6,
          max_capacity: 6,
          table_type: 'regular',
          operational_status: 'normal',
          active: true,
          can_combine: true,
          table_group: table_group,
          sort_order: 2
        )

        # 更新總容量
        restaurant.calculate_and_cache_capacity
      end
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

    trait :with_reservation_periods do
      after(:create) do |restaurant|
        # 創建基本的午餐和晚餐時段
        # 為每個星期創建午餐時段
        (0..6).each do |weekday|
          restaurant.reservation_periods.create!(
            name: '午餐',
            start_time: '11:30',
            end_time: '14:30',
            weekday: weekday,
            active: true,
            status: 'active'
          )
        end

        # 為每個星期創建晚餐時段
        (0..6).each do |weekday|
          restaurant.reservation_periods.create!(
            name: '晚餐',
            start_time: '17:30',
            end_time: '21:30',
            weekday: weekday,
            active: true,
            status: 'active'
          )
        end
      end
    end

    trait :with_more_tables do
      after(:create) do |restaurant|
        # 獲取現有的table group或創建新的
        table_group = restaurant.table_groups.first || restaurant.table_groups.create!(
          name: '擴充用餐區',
          description: '額外用餐區域',
          sort_order: 2,  
          active: true
        )

        # 創建額外的餐桌
        restaurant.restaurant_tables.create!(
          table_number: 'A1',
          capacity: 2,
          max_capacity: 4,
          table_type: 'regular',
          operational_status: 'normal',
          active: true,
          can_combine: true,
          table_group: table_group,
          sort_order: 3
        )

        restaurant.restaurant_tables.create!(
          table_number: 'A2',
          capacity: 8,
          max_capacity: 10,
          table_type: 'large',
          operational_status: 'normal',
          active: true,
          can_combine: true,
          table_group: table_group,
          sort_order: 4
        )

        # 更新總容量
        restaurant.calculate_and_cache_capacity
      end
    end

    # 保留舊的 trait 名稱作為別名
    trait :with_tables do
      with_more_tables
    end
  end
end
