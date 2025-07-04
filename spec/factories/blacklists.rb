FactoryBot.define do
  factory :blacklist do
    restaurant
    added_by factory: %i[user]
    customer_name { '張小明' }
    customer_phone { "09#{rand(10_000_000..99_999_999)}" }
    reason { '多次無故取消訂位' }
    active { true }
  end
end
