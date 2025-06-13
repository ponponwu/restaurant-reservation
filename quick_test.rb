require_relative 'config/environment'

restaurant = Restaurant.first
policy = restaurant.reservation_policy

puts "當前狀態: #{policy.reservation_enabled?}"
puts "模擬關閉..."
policy.update!(reservation_enabled: false)
puts "關閉後狀態: #{policy.reservation_enabled?}"
puts "模擬開啟..."
policy.update!(reservation_enabled: true)
puts "開啟後狀態: #{policy.reservation_enabled?}" 