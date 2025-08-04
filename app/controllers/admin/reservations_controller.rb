class Admin::ReservationsController < Admin::BaseController
  before_action :set_restaurant
  before_action :set_reservation, only: %i[show edit update destroy confirm cancel complete no_show]
  before_action :set_form_data, only: %i[new edit create update]

  def index
    @q = @restaurant.reservations.ransack(params[:q])
    reservations_query = @q.result.includes(:table, :reservation_period)

    # 處理日期篩選，預設顯示今天的訂位
    if params[:show_all] == 'true'
      # 顯示全部訂位，不進行日期篩選
      @filter_date = nil
      @show_all = true
    elsif params[:date_filter].present?
      begin
        @filter_date = Date.parse(params[:date_filter])
        reservations_query = reservations_query.where(
          reservation_datetime: @filter_date.all_day
        )
        @show_all = false
      rescue ArgumentError
        # 如果日期格式無效，回退到顯示今天的訂位
        @filter_date = Date.current
        reservations_query = reservations_query.where(
          reservation_datetime: @filter_date.all_day
        )
        @show_all = false
        flash.now[:alert] = '無效的日期格式，已顯示今天的訂位'
      end
    else
      # 預設顯示今天的訂位
      @filter_date = Date.current
      reservations_query = reservations_query.where(
        reservation_datetime: @filter_date.all_day
      )
      @show_all = false
    end

    # 取得所有訂位並按最新訂單排序（新到舊）
    @pagy, @reservations = pagy(reservations_query.order(reservation_datetime: :desc), items: 20)

    respond_to do |format|
      format.html
      format.turbo_stream do
        render turbo_stream: turbo_stream.update('reservations-container',
                                                 partial: 'reservations_table',
                                                 locals: {
                                                   reservations: @reservations
                                                 })
      end
      format.json { render json: @reservations }
    end
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: @reservation }
    end
  end

  def new
    @reservation = @restaurant.reservations.build

    # 檢查是否為複製訂位
    return if params[:copy_from].blank?

    original_reservation = @restaurant.reservations.find_by(id: params[:copy_from])
    return unless original_reservation

    @reservation.assign_attributes(
      customer_name: original_reservation.customer_name,
      customer_phone: original_reservation.customer_phone,
      customer_email: original_reservation.customer_email,
      party_size: original_reservation.party_size,
      adults_count: original_reservation.adults_count,
      children_count: original_reservation.children_count,
      special_requests: original_reservation.special_requests
    )
    flash.now[:info] = "已複製 #{original_reservation.customer_name} 的訂位資訊，請確認並調整日期時間"
  end

  def edit; end

  def create
    # 先處理時間組合邏輯，避免 Unpermitted parameter 警告
    # 如果有 reservation_time，使用 reservation_datetime 來設定完整時間
    if params[:reservation][:reservation_time].present? && params[:reservation][:reservation_datetime].present?
      # 解析完整的日期時間
      parsed_datetime = parse_time_in_timezone(params[:reservation][:reservation_datetime])
      # 更新參數中的 reservation_datetime，移除 reservation_time
      params[:reservation][:reservation_datetime] = parsed_datetime&.strftime('%Y-%m-%d %H:%M:%S')
      params[:reservation].delete(:reservation_time)
    end

    # 現在可以安全地調用 reservation_params
    @reservation = @restaurant.reservations.build(reservation_params)

    # 複製訂位功能
    if params[:copy_from].present?
      source_reservation = @restaurant.reservations.find(params[:copy_from])
      @reservation.assign_attributes(
        customer_name: source_reservation.customer_name,
        customer_phone: source_reservation.customer_phone,
        customer_email: source_reservation.customer_email,
        party_size: source_reservation.party_size,
        adults_count: source_reservation.adults_count,
        children_count: source_reservation.children_count,
        special_requests: source_reservation.special_requests
      )
    end

    # 自動確定營業時段
    if @reservation.reservation_datetime.present? && @reservation.reservation_period_id.blank?
      @reservation.reservation_period_id = determine_reservation_period(@reservation.reservation_datetime)
    end

    # 檢查是否有 admin_override 參數（用於跳過驗證）
    params[:admin_override]

    # 所有後台建立的訂位都標記為管理員建立
    @reservation.admin_override = true

    # 設定訂位為已確認狀態
    @reservation.status = :confirmed

    if @reservation.save
      # 後台手動創建訂位必須指定桌位，不再使用自動分配
      if @reservation.table_id.present?
        Rails.logger.info "管理後台 - 手動指定桌位 #{@reservation.table.table_number} 給訂位 #{@reservation.id}"
        success_message = '訂位建立成功，已指定桌位'
      else
        # 理論上不應該到這裡，因為桌位已設為必填
        Rails.logger.error "管理後台 - 訂位 #{@reservation.id} 建立時未指定桌位"
        success_message = '訂位建立成功，但未指定桌位'
      end

      respond_to do |format|
        format.html do
          # 取得訂位日期，用於跳轉回該日期的訂位列表
          reservation_date = @reservation.reservation_datetime.to_date
          redirect_to admin_restaurant_reservations_path(@restaurant, date_filter: reservation_date.strftime('%Y-%m-%d')),
                      notice: success_message
        end
        format.turbo_stream do
          # 取得訂位日期，用於跳轉回該日期的訂位列表
          reservation_date = @reservation.reservation_datetime.to_date
          redirect_to admin_restaurant_reservations_path(@restaurant, date_filter: reservation_date.strftime('%Y-%m-%d')),
                      notice: success_message
        end
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def update
    # 儲存原始人數，用於檢查是否需要重新分配桌位
    original_party_size = @reservation.party_size
    original_datetime = @reservation.reservation_datetime

    # 處理大人數和小孩數的自動調整
    params_to_update = reservation_params

    # 處理時區問題 - 確保使用台北時區
    if params[:reservation][:reservation_datetime].present?
      params_to_update = params_to_update.except(:reservation_datetime)
      @reservation.reservation_datetime = parse_time_in_timezone(params[:reservation][:reservation_datetime])
    end

    # 如果只更新了 party_size，需要調整 adults_count 和 children_count
    if params_to_update[:party_size].present?
      new_party_size = params_to_update[:party_size].to_i
      current_total = @reservation.adults_count.to_i + @reservation.children_count.to_i

      # 如果新的總人數與現有的大人+小孩數不同，需要調整
      if new_party_size != current_total
        # 保持小孩數不變，調整大人數
        children_count = @reservation.children_count.to_i
        adults_count = [new_party_size - children_count, 1].max # 至少要有1個大人

        # 如果計算出的大人數加小孩數超過新的總人數，則調整小孩數
        children_count = [new_party_size - adults_count, 0].max if adults_count + children_count > new_party_size

        params_to_update = params_to_update.merge(
          adults_count: adults_count,
          children_count: children_count
        )
      end
    end

    # 檢查是否有 admin_override 參數
    admin_override = params[:admin_override] == 'true'

    if @reservation.update(params_to_update)
      # 檢查是否需要重新分配桌位
      new_party_size = @reservation.party_size
      new_datetime = @reservation.reservation_datetime

      if (new_party_size != original_party_size || new_datetime != original_datetime) && !admin_override
        # 嘗試重新分配桌位
        reallocate_table_for_reservation(@reservation)
      end

      respond_to do |format|
        format.html do
          redirect_to admin_restaurant_reservations_path(@restaurant),
                      notice: '訂位已更新成功'
        end
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("reservation_#{@reservation.id}",
                                 partial: 'reservation_row',
                                 locals: { reservation: @reservation }),
            turbo_stream.update('flash',
                                partial: 'shared/flash',
                                locals: { message: '訂位已更新成功', type: 'success' })
          ]
        end
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('flash',
                                                   partial: 'shared/flash',
                                                   locals: { message: @reservation.errors.full_messages.join(', '),
                                                             type: 'error' })
        end
      end
    end
  end

  def destroy
    @reservation.destroy!
    redirect_to admin_restaurant_reservations_path(@restaurant),
                notice: '訂位已刪除'
  end

  # 狀態管理方法
  def cancel
    if @reservation.update(status: :cancelled)
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), notice: '訂位已取消' }
        format.turbo_stream # 使用 cancel.turbo_stream.erb 模板
        format.json { render json: { status: 'success', message: '訂位已取消' } }
      end
    else
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), alert: '取消訂位失敗' }
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('flash_messages',
                                                   partial: 'shared/flash',
                                                   locals: { alert: "取消訂位失敗：#{@reservation.errors.full_messages.join(', ')}" })
        end
        format.json { render json: { status: 'error', message: '取消訂位失敗', errors: @reservation.errors.full_messages } }
      end
    end
  end

  def no_show
    if @reservation.update(status: :no_show)
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), notice: '已標記為未出席' }
        format.turbo_stream # 使用 no_show.turbo_stream.erb 模板
        format.json { render json: { status: 'success', message: '已標記為未出席' } }
      end
    else
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), alert: '標記未出席失敗' }
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('flash_messages',
                                                   partial: 'shared/flash',
                                                   locals: { alert: "標記未出席失敗：#{@reservation.errors.full_messages.join(', ')}" })
        end
        format.json { render json: { status: 'error', message: '標記未出席失敗', errors: @reservation.errors.full_messages } }
      end
    end
  end

  def search
    @q = @restaurant.reservations.ransack(params[:q])
    @reservations = @q.result
      .includes(:table, :reservation_period)
      .order(reservation_datetime: :desc)
      .limit(50)

    respond_to do |format|
      format.html { render :index }
      format.json { render json: @reservations }
    end
  end

  private

  # 解析時間並確保使用台北時區
  def parse_time_in_timezone(datetime_string)
    return nil if datetime_string.blank?

    begin
      # 使用 Time.zone.parse 確保時間被解析為台北時區
      Time.zone.parse(datetime_string)
    rescue ArgumentError => e
      Rails.logger.error "時間解析錯誤: #{e.message}, 輸入: #{datetime_string}"
      nil
    end
  end

  def set_restaurant
    # 嘗試用 ID 查找，如果失敗則用 slug 查找
    @restaurant = if params[:restaurant_id].to_i.positive?
                    Restaurant.find(params[:restaurant_id])
                  else
                    Restaurant.find_by!(slug: params[:restaurant_id])
                  end
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_restaurants_path, alert: '找不到指定的餐廳'
  end

  def determine_reservation_period(datetime)
    return nil unless datetime

    # 確保使用台北時區的時間來比較
    taipei_time = datetime.in_time_zone('Asia/Taipei')

    # 檢查是否在營業時段內 - 直接使用Ruby邏輯避免時區問題
    time_minutes = (taipei_time.hour * 60) + taipei_time.min

    matching_period = @restaurant.reservation_periods.active.find do |period|
      start_minutes = (period.start_time.hour * 60) + period.start_time.min
      end_minutes = (period.end_time.hour * 60) + period.end_time.min
      time_minutes >= start_minutes && time_minutes <= end_minutes
    end

    # 如果找不到完全匹配的時段，找最接近即將開始的時段
    if matching_period.blank?
      periods = @restaurant.reservation_periods.active.order(:start_time)

      matching_period = periods.min_by do |period|
        start_minutes = (period.start_time.hour * 60) + period.start_time.min
        end_minutes = (period.end_time.hour * 60) + period.end_time.min

        if time_minutes < start_minutes
          # 時間在時段開始前，計算距離開始的時間
          start_minutes - time_minutes
        elsif time_minutes > end_minutes
          # 時間在時段結束後，給一個較大的距離值，優先選擇即將開始的時段
          (time_minutes - end_minutes) + 180 # 加3小時懲罰
        else
          # 理論上不會走到這裡
          0
        end
      end
    end

    matching_period&.id
  end

  def set_reservation
    @reservation = @restaurant.reservations.find(params[:id])
  end

  def set_form_data
    @reservation_periods = @restaurant.reservation_periods.active
    @available_tables = @restaurant.restaurant_tables.active.ordered
  end

  def reservation_params
    params.require(:reservation).permit(
      :customer_name, :customer_phone, :customer_email,
      :party_size, :adults_count, :children_count,
      :reservation_datetime, :status, :notes, :special_requests,
      :table_id, :reservation_period_id, :admin_override
    )
  end

  # 為訂位分配桌位
  def allocate_table_for_reservation(reservation, admin_override = false)
    Rails.logger.info "🔧 開始為訂位 #{reservation.id} 分配桌位，人數：#{reservation.party_size}，時間：#{reservation.reservation_datetime}，餐期：#{reservation.reservation_period_id}，強制模式：#{admin_override}"

    allocator = ReservationAllocatorService.new({
                                                  restaurant: @restaurant,
                                                  party_size: reservation.party_size,
                                                  adults: reservation.adults_count || reservation.party_size,
                                                  children: reservation.children_count || 0,
                                                  reservation_datetime: reservation.reservation_datetime,
                                                  reservation_period_id: reservation.reservation_period_id
                                                })

    # 檢查可用性（管理員強制模式下可以跳過）
    if admin_override
      Rails.logger.info "管理後台 - 強制模式：跳過可用性檢查，為訂位 #{reservation.id} 分配桌位"
    else
      Rails.logger.info '🔧 檢查可用性...'
      availability_check = allocator.check_availability
      Rails.logger.info "🔧 可用性檢查結果：#{availability_check}"

      unless availability_check[:has_availability]
        Rails.logger.warn "管理後台 - 無法為訂位 #{reservation.id} 分配桌位：無可用性"
        return false
      end
    end

    Rails.logger.info '🔧 開始分配桌位...'
    allocated_table = allocator.allocate_table
    Rails.logger.info "🔧 分配結果：#{allocated_table.inspect}"

    if allocated_table
      if allocated_table.is_a?(Array)
        # 併桌情況 - 創建 TableCombination
        Rails.logger.info "🔧 分配到併桌：#{allocated_table.map(&:table_number).join(', ')}"
        combination = TableCombination.new(
          reservation: reservation,
          name: "併桌 #{allocated_table.map(&:table_number).join('+')}"
        )

        # 建立桌位關聯
        allocated_table.each do |table|
          combination.table_combination_tables.build(restaurant_table: table)
        end

        if combination.save
          Rails.logger.info "管理後台 - 分配併桌給訂位 #{reservation.id}: #{allocated_table.map(&:table_number).join(', ')}"
          # 設定主桌位（用於相容性）
          reservation.table = allocated_table.first
          true
        else
          Rails.logger.error "管理後台 - 創建併桌組合失敗: #{combination.errors.full_messages.join(', ')}"
          false
        end
      else
        # 單桌情況
        Rails.logger.info "🔧 分配到單桌：#{allocated_table.table_number}"
        reservation.table = allocated_table
        Rails.logger.info "管理後台 - 分配桌位 #{allocated_table.table_number} 給訂位 #{reservation.id}"
        true
      end
    else
      Rails.logger.warn '🔧 allocator.allocate_table 回傳 nil'
      if admin_override
        # 強制模式下，即使沒有找到桌位，也允許建立訂位
        Rails.logger.info "管理後台 - 強制模式：無法找到合適桌位，但允許建立訂位 #{reservation.id}（無桌位分配）"
        true
      else
        Rails.logger.warn "管理後台 - 無法為訂位 #{reservation.id} 找到合適的桌位"
        false
      end
    end
  end

  # 重新分配桌位
  def reallocate_table_for_reservation(reservation)
    # 先清除現有的桌位分配
    old_table = reservation.table
    old_combination = reservation.table_combination

    reservation.table = nil
    reservation.table_combination&.destroy

    # 嘗試重新分配
    allocate_table_for_reservation(reservation)

    # 如果重新分配失敗，恢復原有分配（如果有的話）
    unless reservation.table.present? || reservation.table_combination.present?
      if old_table
        reservation.table = old_table
        Rails.logger.warn "重新分配桌位失敗，恢復原桌位 #{old_table.table_number}"
      elsif old_combination
        # 併桌的恢復比較複雜，暫時記錄即可
        Rails.logger.warn '重新分配桌位失敗，原為併桌無法恢復'
      end
    end

    reservation.save
  end
end
