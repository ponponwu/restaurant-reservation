FactoryBot.define do
  factory :reservation do
    restaurant
    reservation_period

    sequence(:customer_name) { |n| "顧客#{n}" }
    sequence(:customer_phone) { |n| "0912#{format('%06d', n)}" }
    sequence(:customer_email) { |n| "customer#{n}@example.com" }

    party_size { 2 }
    adults_count { 2 }
    children_count { 0 }
    sequence(:reservation_datetime) { |n| (n.days.from_now + (n * 8).hours).change(min: 0) }
    status { 'pending' }
    special_requests { '' }
    notes { '' }
    admin_override { true }  # 跳過容量檢查

    # 確保 table 和 reservation_period 屬於同一餐廳
    after(:build) do |reservation|
      # 確保 reservation_period 屬於正確的餐廳
      if reservation.reservation_period && reservation.reservation_period.restaurant != reservation.restaurant
        reservation.reservation_period = FactoryBot.create(:reservation_period, restaurant: reservation.restaurant)
      elsif !reservation.reservation_period
        reservation.reservation_period = FactoryBot.create(:reservation_period, restaurant: reservation.restaurant)
      end

      # 只有在沒有指定桌位時才自動分配桌位
      unless reservation.table
        if reservation.restaurant.restaurant_tables.active.any?
          reservation.table = reservation.restaurant.restaurant_tables.active.first
        else
          # 如果餐廳沒有桌位，創建一張
          table_group = reservation.restaurant.table_groups.first || FactoryBot.create(:table_group, restaurant: reservation.restaurant)
          reservation.table = FactoryBot.create(:table, restaurant: reservation.restaurant, table_group: table_group)
        end
      end
    end

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
