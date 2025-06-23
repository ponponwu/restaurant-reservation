FactoryBot.define do
  factory :table, class: 'RestaurantTable' do
    restaurant
    table_group

    sequence(:table_number) { |n| "Table-#{n}" }
    capacity { 4 }
    min_capacity { 1 }
    max_capacity { 4 }
    table_type { 'regular' }
    sequence(:sort_order) { |n| n }
    status { 'available' }
    operational_status { 'normal' }
    active { true }
    can_combine { false }

    trait :window_round_table do
      table_number { '窗邊圓桌' }
      capacity { 5 }
      min_capacity { 4 }
      max_capacity { 5 }
      table_type { 'round' }
    end

    trait :square_table do
      table_number { '方桌A' }
      capacity { 2 }
      min_capacity { 1 }
      max_capacity { 2 }
      table_type { 'square' }
    end

    trait :bar_seat do
      table_number { '吧台A' }
      capacity { 1 }
      min_capacity { 1 }
      max_capacity { 1 }
      table_type { 'bar' }
    end

    trait :large_table do
      capacity { 8 }
      min_capacity { 6 }
      max_capacity { 8 }
    end

    trait :occupied do
      status { 'occupied' }
      # occupied 狀態透過訂位記錄表達，operational_status 保持 normal
      operational_status { 'normal' }
    end

    trait :maintenance do
      status { 'maintenance' }
      operational_status { 'maintenance' }
    end

    trait :cleaning do
      status { 'cleaning' }
      operational_status { 'cleaning' }
    end

    trait :out_of_service do
      operational_status { 'out_of_service' }
    end

    trait :inactive do
      active { false }
    end
  end
end
