FactoryBot.define do
  factory :reservation_slot do
    business_period
    slot_time { Time.zone.parse('18:00') }
    max_capacity { 20 }
    interval_minutes { 30 }
    reservation_deadline { 120 }
    active { true }
  end
end