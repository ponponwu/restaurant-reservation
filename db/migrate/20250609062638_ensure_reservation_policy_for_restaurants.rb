class EnsureReservationPolicyForRestaurants < ActiveRecord::Migration[7.1]
  def up
    Restaurant.find_each do |restaurant|
      unless restaurant.reservation_policy
        restaurant.create_reservation_policy!(
          advance_booking_days: 30,
          minimum_advance_hours: 2,
          max_party_size: 10,
          min_party_size: 1,
          deposit_required: false,
          deposit_amount: 0.0,
          deposit_per_person: false,
          cancellation_hours: 24
        )
        
        puts "Created reservation policy for restaurant: #{restaurant.name}"
      end
    end
  end

  def down
    # 不需要回滾操作，因為我們不想刪除已建立的預約政策
  end
end
