module ReservationTestHelpers
  # 建立完整的餐廳設定，包含營業時段、桌位等
  def setup_restaurant_with_capacity(restaurant, options = {})
    table_count = options[:table_count] || 3
    table_capacity = options[:table_capacity] || 4

    # 確保有營業時段
    unless restaurant.business_periods.any?
      create(:business_period,
             restaurant: restaurant,
             name: 'dinner',
             display_name: '晚餐',
             start_time: '17:30',
             end_time: '21:30')
    end

    # 確保有桌位群組
    table_group = restaurant.table_groups.first ||
                  restaurant.table_groups.create!(
                    name: '主要區域',
                    description: '主要用餐區域',
                    active: true
                  )

    # 建立桌位
    table_count.times do |i|
      restaurant.restaurant_tables.create!(
        table_number: "T#{i + 1}",
        capacity: table_capacity,
        min_capacity: 1,
        max_capacity: table_capacity,
        table_group: table_group,
        active: true
      )
    end

    # 確保訂位政策啟用
    restaurant.reservation_policy.update!(reservation_enabled: true)

    restaurant.reload
  end

  # 建立標準的訂位參數
  def build_reservation_params(overrides = {})
    defaults = {
      reservation: {
        customer_name: '測試客戶',
        customer_phone: '0912345678',
        customer_email: 'test@example.com'
      },
      date: 2.days.from_now.strftime('%Y-%m-%d'),
      time_slot: '18:00',
      adults: 2,
      children: 0
    }

    params = defaults.deep_merge(overrides)

    # 自動添加 business_period_id 如果沒有提供
    if params[:business_period_id].nil? && defined?(@restaurant)
      params[:business_period_id] = @restaurant.business_periods.first&.id
    elsif params[:business_period_id].nil? && defined?(restaurant)
      params[:business_period_id] = restaurant.business_periods.first&.id
    end

    params
  end

  # 建立訂位並返回結果
  def create_reservation_via_api(restaurant, params = {})
    reservation_params = build_reservation_params(params)

    post restaurant_reservations_path(restaurant.slug), params: reservation_params

    {
      response: response,
      reservation: Reservation.last,
      success: response.status == 302
    }
  end

  # 設定餐廳休息日
  def setup_closure_dates(restaurant, dates = {})
    # 週休息日
    if dates[:weekly_closures]
      days_mask = 127 # 全週營業
      dates[:weekly_closures].each do |day|
        days_mask &= ~(2**day) # 移除指定的天
      end

      restaurant.business_periods.update_all(days_of_week_mask: days_mask)
    end

    # 特殊休息日
    return unless dates[:special_closures]

    dates[:special_closures].each do |date|
      restaurant.closure_dates.create!(
        date: date,
        reason: '測試公休',
        all_day: true
      )
    end
  end

  # 建立黑名單記錄
  def setup_blacklist(restaurant, phone_numbers)
    Array(phone_numbers).each do |phone|
      create(:blacklist,
             restaurant: restaurant,
             customer_phone: phone,
             reason: '測試黑名單')
    end
  end

  # 設定訂位限制
  def setup_booking_limits(restaurant, options = {})
    restaurant.reservation_policy.update!(
      max_bookings_per_phone: options[:max_per_phone] || 2,
      phone_limit_period_days: options[:period_days] || 30,
      min_party_size: options[:min_party_size] || 1,
      max_party_size: options[:max_party_size] || 10,
      advance_booking_days: options[:advance_days] || 30,
      minimum_advance_hours: options[:min_hours] || 24
    )
  end

  # 建立現有訂位來測試限制
  def create_existing_reservations(restaurant, phone, count = 1)
    count.times do |i|
      create(:reservation,
             restaurant: restaurant,
             customer_phone: phone,
             reservation_datetime: (i + 3).days.from_now,
             status: :confirmed)
    end
  end

  # 模擬併發訂位
  def simulate_concurrent_reservations(restaurant, count = 2, params = {})
    threads = []
    results = []

    count.times do |i|
      threads << Thread.new do
        reservation_params = build_reservation_params(params.merge(
                                                        reservation: params[:reservation] || {}
                                                      ))

        # 為每個請求使用不同的手機號碼
        phone = reservation_params.dig(:reservation, :customer_phone) || '0912345678'
        reservation_params[:reservation][:customer_phone] = "#{phone[0..-2]}#{i}"

        begin
          post restaurant_reservations_path(restaurant.slug), params: reservation_params
          results << {
            success: response.status == 302,
            status: response.status,
            thread_id: Thread.current.object_id
          }
        rescue StandardError => e
          results << {
            success: false,
            error: e.message,
            thread_id: Thread.current.object_id
          }
        end
      end
    end

    threads.each(&:join)
    results
  end

  # 驗證錯誤訊息
  def expect_generic_error_message(response_body)
    expect(response_body).to include('訂位失敗，請聯繫餐廳')
    expect(response_body).not_to include('黑名單')
    expect(response_body).not_to include('blacklist')
    expect(response_body).not_to include('訂位次數已達上限')
    expect(response_body).not_to include('limit')
  end

  # 模擬系統測試中的日期選擇
  def select_date_in_calendar(date, wait_time = 5)
    find('input[data-reservation-target="date"]').click

    expect(page).to have_css('.flatpickr-calendar', wait: wait_time)

    within('.flatpickr-calendar') do
      date_element = find(".flatpickr-day[aria-label*='#{date.strftime('%B %-d, %Y')}']", wait: 3)
      date_element.click
    end
  end

  # 填寫完整的訂位表單
  def fill_reservation_form(options = {})
    fill_in '聯絡人姓名', with: options[:name] || '測試客戶'
    fill_in '聯絡電話', with: options[:phone] || '0912345678'
    fill_in '電子郵件', with: options[:email] || 'test@example.com'

    return unless options[:special_requests]

    fill_in '特殊需求', with: options[:special_requests]
  end

  # 驗證訂位建立成功
  def expect_reservation_success(restaurant)
    expect(page).to have_current_path(restaurant_public_path(restaurant.slug))
    expect(page).to have_content('訂位建立成功')

    reservation = Reservation.last
    expect(reservation).to be_present
    expect(reservation.cancellation_token).to be_present
  end

  # 驗證訂位建立失敗
  def expect_reservation_failure(error_message = nil)
    expect(page).to have_current_path(/reservation/)

    if error_message
      expect(page).to have_content(error_message)
    else
      expect(page).to have_css('.bg-red-50') # 錯誤樣式
    end
  end

  # Mock 外部服務
  def mock_availability_service(slots = [])
    default_slots = [
      {
        period_name: '晚餐時段',
        time: '18:00',
        available: true,
        business_period_id: @restaurant&.business_periods&.first&.id || 1
      }
    ]

    allow_any_instance_of(AvailabilityService)
      .to receive(:get_available_slots_by_period)
      .and_return(slots.any? ? slots : default_slots)
  end

  def mock_allocator_service(result = nil)
    if result.nil?
      # 預設成功分配第一個桌位
      table = @restaurant&.restaurant_tables&.first || create(:table)
      allow_any_instance_of(ReservationAllocatorService)
        .to receive(:allocate_table)
        .and_return(table)

      allow_any_instance_of(ReservationAllocatorService)
        .to receive(:check_availability)
        .and_return({ has_availability: true })
    else
      allow_any_instance_of(ReservationAllocatorService)
        .to receive(:allocate_table)
        .and_return(result)

      availability = result ? { has_availability: true } : { has_availability: false }
      allow_any_instance_of(ReservationAllocatorService)
        .to receive(:check_availability)
        .and_return(availability)
    end
  end

  # 效能測試輔助方法
  def measure_response_time
    start_time = Time.current
    yield
    end_time = Time.current
    end_time - start_time
  end

  def expect_fast_response(max_seconds = 1, &block)
    response_time = measure_response_time(&block)
    expect(response_time).to be < max_seconds.seconds
  end
end

# 在所有測試中包含這些輔助方法
RSpec.configure do |config|
  config.include ReservationTestHelpers
end
