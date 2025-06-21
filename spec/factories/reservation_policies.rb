FactoryBot.define do
  factory :reservation_policy do
    restaurant

    # 基本預約設定
    advance_booking_days { 30 }
    minimum_advance_hours { 2 }
    max_party_size { 10 }
    min_party_size { 1 }
    cancellation_hours { 24 }

    # 押金設定
    deposit_required { false }
    deposit_amount { 0.0 }
    deposit_per_person { false }

    # 手機號碼限制
    max_bookings_per_phone { 5 }
    phone_limit_period_days { 30 }

    # 訂位功能開關
    reservation_enabled { true }

    # 政策文字
    no_show_policy { '未到場將記錄於黑名單' }
    modification_policy { '用餐前24小時可免費修改' }
    special_rules { {} }

    # 變體工廠
    trait :with_deposit do
      deposit_required { true }
      deposit_amount { 200.0 }
      deposit_per_person { false }
    end

    trait :with_per_person_deposit do
      deposit_required { true }
      deposit_amount { 100.0 }
      deposit_per_person { true }
    end

    trait :strict_booking_limits do
      advance_booking_days { 7 }
      minimum_advance_hours { 24 }
      max_party_size { 6 }
      min_party_size { 2 }
    end

    trait :phone_limit_strict do
      max_bookings_per_phone { 2 }
      phone_limit_period_days { 7 }
    end

    trait :reservation_disabled do
      reservation_enabled { false }
    end

    trait :relaxed_limits do
      advance_booking_days { 60 }
      minimum_advance_hours { 1 }
      max_party_size { 20 }
      min_party_size { 1 }
      max_bookings_per_phone { 10 }
      phone_limit_period_days { 90 }
    end

    # 組合工廠
    factory :strict_reservation_policy, traits: %i[strict_booking_limits with_deposit phone_limit_strict]
    factory :relaxed_reservation_policy, traits: [:relaxed_limits]
    factory :disabled_reservation_policy, traits: [:reservation_disabled]
  end
end
