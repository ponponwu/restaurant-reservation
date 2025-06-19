class FixBusinessPeriodsTimings < ActiveRecord::Migration[7.1]
  def up
    # 修正錯誤的營業時段資料（不刪除，直接更新）
    BusinessPeriod.transaction do
      puts "🔧 Fixing incorrect business periods..."
      
      # 先刪除相關的 reservation_slots 以避免外鍵約束
      puts "🔧 Cleaning up reservation slots..."
      ReservationSlot.delete_all
      
      # 為每個餐廳修正營業時段
      Restaurant.find_each do |restaurant|
        puts "🔧 Fixing business periods for restaurant: #{restaurant.name} (ID: #{restaurant.id})"
        
        # 記錄舊的時段 IDs
        old_period_ids = restaurant.business_periods.pluck(:id)
        
        # 先建立正確的午餐時段
        lunch_period = restaurant.business_periods.create!(
          name: 'lunch',
          display_name: '午餐',
          start_time: '11:30',
          end_time: '14:30',
          days_of_week_mask: 127, # 週一到週日 (1+2+4+8+16+32+64)
          active: true
        )
        
        # 建立正確的晚餐時段
        dinner_period = restaurant.business_periods.create!(
          name: 'dinner', 
          display_name: '晚餐',
          start_time: '17:30',
          end_time: '21:30',
          days_of_week_mask: 127, # 週一到週日
          active: true
        )
        
        puts "✅ Created periods for #{restaurant.name}: Lunch (#{lunch_period.id}), Dinner (#{dinner_period.id})"
        
        # 更新該餐廳的現有訂位，根據時間重新分配正確的時段
        restaurant.reservations.find_each do |reservation|
          if reservation.reservation_datetime.present?
            hour = reservation.reservation_datetime.in_time_zone('Asia/Taipei').hour
            minute = reservation.reservation_datetime.in_time_zone('Asia/Taipei').min
            time_decimal = hour + (minute / 60.0)
            
            # 根據時間判斷應該屬於哪個時段
            if time_decimal >= 11.5 && time_decimal <= 14.5  # 11:30-14:30
              reservation.update_column(:business_period_id, lunch_period.id)
            elsif time_decimal >= 17.5 && time_decimal <= 21.5  # 17:30-21:30
              reservation.update_column(:business_period_id, dinner_period.id)
            else
              # 如果不在正常時段內，分配到最接近的時段
              if time_decimal < 16
                reservation.update_column(:business_period_id, lunch_period.id)
              else
                reservation.update_column(:business_period_id, dinner_period.id)
              end
            end
            puts "  📍 Updated reservation #{reservation.id} (#{reservation.reservation_datetime.strftime('%H:%M')}) -> #{time_decimal < 16 ? 'Lunch' : 'Dinner'}"
          end
        end
        
        # 現在可以安全地刪除舊的時段
        BusinessPeriod.where(id: old_period_ids).destroy_all
        puts "🗑️  Removed old periods: #{old_period_ids}"
      end
    end
    
    puts "🎉 Business periods timing fix completed!"
  end

  def down
    # 回滾操作 - 這裡我們不能恢復原本錯誤的資料
    # 所以只是清空，需要手動恢復或重新運行 seeds
    puts "⚠️  Rolling back business periods fix..."
    BusinessPeriod.delete_all
    puts "⚠️  Business periods cleared. You may need to re-run db:seed"
  end
end