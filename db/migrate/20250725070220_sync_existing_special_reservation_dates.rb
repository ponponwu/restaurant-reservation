class SyncExistingSpecialReservationDates < ActiveRecord::Migration[8.0]
  def up
    puts "開始同步現有的 SpecialReservationDate 記錄..."
    
    # 重新啟用回調，確保同步機制正常運作
    SpecialReservationDate.reset_callbacks(:save)
    
    # 載入所有有 custom_hours 的特殊日期
    special_dates = SpecialReservationDate.where(operation_mode: 'custom_hours')
                                         .where.not(custom_periods: [nil, []])
    
    puts "找到 #{special_dates.count} 個需要同步的特殊日期記錄"
    
    special_dates.find_each do |special_date|
      begin
        puts "同步 SpecialReservationDate ID: #{special_date.id} - #{special_date.name}"
        
        # 觸發同步邏輯（模擬 save 觸發的回調）
        special_date.send(:sync_reservation_periods) if special_date.custom_hours?
        
        periods_count = special_date.reservation_periods.count
        total_slots_count = special_date.reservation_periods.joins(:reservation_slots).count
        
        puts "  ✓ 建立了 #{periods_count} 個 ReservationPeriod"
        puts "  ✓ 建立了 #{total_slots_count} 個 ReservationSlot"
        
      rescue StandardError => e
        puts "  ✗ 同步失敗: #{e.message}"
        puts "    錯誤詳情: #{e.backtrace.first(3).join("\n    ")}"
      end
    end
    
    puts "同步完成！"
  end

  def down
    puts "回滾：清除所有特殊日期相關的 ReservationPeriod 記錄..."
    
    # 刪除所有特殊日期相關的 ReservationPeriod（會連帶刪除 ReservationSlot）
    deleted_count = ReservationPeriod.where(is_special_date_period: true).delete_all
    puts "已刪除 #{deleted_count} 個特殊日期的 ReservationPeriod 記錄"
  end
  
  private
  
  # 在遷移中重新定義關鍵方法，避免依賴外部模型變更
  def sync_reservation_periods_for(special_date)
    return unless special_date.operation_mode == 'custom_hours' && special_date.custom_periods.present?
    
    # 清除現有的特殊日期 ReservationPeriod
    special_date.reservation_periods.where(is_special_date_period: true).destroy_all
    
    # 為每個 custom_period 建立 ReservationPeriod
    special_date.custom_periods.each_with_index do |period, index|
      create_reservation_period_for_custom_period(special_date, period, index)
    end
  end
  
  def create_reservation_period_for_custom_period(special_date, period, index)
    start_time = Time.parse(period['start_time'])
    end_time = Time.parse(period['end_time'])
    interval_minutes = period['interval_minutes'].to_i
    
    ReservationPeriod.create!(
      restaurant: special_date.restaurant,
      special_reservation_date: special_date,
      name: "#{special_date.name} - 時段#{index + 1}",
      display_name: "#{special_date.name} - 時段#{index + 1}",
      start_time: start_time,
      end_time: end_time,
      weekday: special_date.start_date.wday,
      date: nil,
      reservation_interval_minutes: interval_minutes,
      is_special_date_period: true,
      custom_period_index: index,
      active: true
    )
  end
end
