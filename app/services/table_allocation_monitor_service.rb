class TableAllocationMonitorService
  class << self
    # 檢測桌位重複分配
    def detect_duplicate_allocations(restaurant_id = nil)
      scope = Reservation.includes(:table, table_combination: :restaurant_tables)
        .where(status: %w[confirmed pending])

      scope = scope.where(restaurant_id: restaurant_id) if restaurant_id

      duplicates = []
      Set.new

      # 按日期分組以提高效率
      scope.group_by { |r| r.reservation_datetime.to_date }.each do |date, reservations|
        duplicates.concat(detect_daily_duplicates(date, reservations))
      end

      duplicates
    end

    # 檢測並記錄重複分配
    def check_and_log_duplicates(restaurant_id = nil)
      duplicates = detect_duplicate_allocations(restaurant_id)

      duplicates.each do |duplicate|
        log_duplicate_allocation(duplicate)

        # 發送警報（如果配置了）
        send_alert(duplicate) if should_send_alert?
      end

      duplicates
    end

    # 修復檢測到的重複分配
    def fix_duplicate_allocations(duplicates)
      fixed_count = 0

      duplicates.each do |duplicate|
        ActiveRecord::Base.transaction do
          fix_single_duplicate(duplicate)
          fixed_count += 1
        end
      rescue StandardError => e
        Rails.logger.error "Failed to fix duplicate allocation: #{duplicate.inspect}, error: #{e.message}"
      end

      Rails.logger.info "Fixed #{fixed_count} duplicate allocations"
      fixed_count
    end

    private

    # 檢測單日的重複分配
    def detect_daily_duplicates(_date, reservations)
      duplicates = []
      table_usage = Hash.new { |h, k| h[k] = [] }

      reservations.each do |reservation|
        tables = get_reservation_tables(reservation)

        tables.each do |table|
          table_usage[table.id] << reservation
        end
      end

      # 檢查每個桌位的時間重疊
      table_usage.each do |_table_id, table_reservations|
        next if table_reservations.size < 2

        overlapping = find_overlapping_reservations(table_reservations)
        duplicates.concat(overlapping) if overlapping.any?
      end

      duplicates.uniq
    end

    # 獲取預訂使用的所有桌位
    def get_reservation_tables(reservation)
      tables = []

      # 直接分配的桌位
      tables << reservation.table if reservation.table

      # 併桌的桌位
      tables.concat(reservation.table_combination.restaurant_tables) if reservation.table_combination

      tables.uniq
    end

    # 查找時間重疊的預訂
    def find_overlapping_reservations(reservations)
      overlapping = []
      duration_minutes = 120 # 默認用餐時間

      reservations.combination(2) do |res1, res2|
        if reservations_overlap?(res1, res2, duration_minutes)
          overlapping << {
            conflict_type: :time_overlap,
            reservations: [res1, res2],
            table_id: get_common_table_id(res1, res2),
            overlap_period: calculate_overlap_period(res1, res2, duration_minutes)
          }
        end
      end

      overlapping
    end

    # 檢查兩個預訂是否時間重疊
    def reservations_overlap?(res1, res2, duration_minutes)
      start1 = res1.reservation_datetime
      end1 = start1 + duration_minutes.minutes
      start2 = res2.reservation_datetime
      end2 = start2 + duration_minutes.minutes

      start1 < end2 && start2 < end1
    end

    # 獲取兩個預訂的共同桌位 ID
    def get_common_table_id(res1, res2)
      tables1 = get_reservation_tables(res1).map(&:id)
      tables2 = get_reservation_tables(res2).map(&:id)

      (tables1 & tables2).first
    end

    # 計算重疊時間段
    def calculate_overlap_period(res1, res2, duration_minutes)
      start1 = res1.reservation_datetime
      end1 = start1 + duration_minutes.minutes
      start2 = res2.reservation_datetime
      end2 = start2 + duration_minutes.minutes

      overlap_start = [start1, start2].max
      overlap_end = [end1, end2].min

      {
        start: overlap_start,
        end: overlap_end,
        duration_minutes: ((overlap_end - overlap_start) / 1.minute).to_i
      }
    end

    # 記錄重複分配
    def log_duplicate_allocation(duplicate)
      Rails.logger.error <<~LOG
        ================================
        DUPLICATE TABLE ALLOCATION DETECTED
        ================================
        Conflict Type: #{duplicate[:conflict_type]}
        Table ID: #{duplicate[:table_id]}
        Reservations:
        #{duplicate[:reservations].map do |r| # {' '}
          "  - ID: #{r.id}, Time: #{r.reservation_datetime}, Customer: #{r.customer_name}, Table: #{r.table_id}"
        end.join("\n")}
        Overlap Period: #{duplicate[:overlap_period][:start]} - #{duplicate[:overlap_period][:end]} (#{duplicate[:overlap_period][:duration_minutes]} minutes)
        ================================
      LOG

      # 可以添加到監控系統（如 New Relic, Datadog 等）
      return unless defined?(NewRelic)

      NewRelic::Agent.record_custom_event(
        'DuplicateTableAllocation',
        {
          table_id: duplicate[:table_id],
          reservation_ids: duplicate[:reservations].map(&:id),
          overlap_duration: duplicate[:overlap_period][:duration_minutes]
        }
      )
    end

    # 發送警報
    def send_alert(duplicate)
      # 這裡可以集成 Slack, Email, SMS 等警報系統
      Rails.logger.warn "ALERT: Duplicate table allocation detected for table #{duplicate[:table_id]}"

      # 示例：發送到 Slack（需要配置 webhook）
      # SlackNotifier.notify_duplicate_allocation(duplicate) if Rails.env.production?
    end

    # 是否應該發送警報
    def should_send_alert?
      Rails.env.production? || ENV['ENABLE_ALLOCATION_ALERTS'] == 'true'
    end

    # 修復單個重複分配
    def fix_single_duplicate(duplicate)
      reservations = duplicate[:reservations]

      # 保留較早創建的預訂，取消較晚的
      older_reservation = reservations.min_by(&:created_at)
      newer_reservations = reservations - [older_reservation]

      newer_reservations.each do |reservation|
        reservation.update!(
          status: 'cancelled',
          notes: "系統自動取消：檢測到桌位重複分配衝突（與預訂 #{older_reservation.id} 衝突）"
        )

        Rails.logger.info "自動取消預訂 #{reservation.id} 以解決桌位衝突"
      end
    end
  end
end
