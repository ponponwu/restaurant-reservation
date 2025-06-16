class Admin::ReservationsController < Admin::BaseController
  before_action :set_restaurant
  before_action :set_reservation, only: [:show, :edit, :update, :destroy, :confirm, :cancel, :complete, :no_show]
  before_action :set_form_data, only: [:new, :edit, :create, :update]

  def index
    @q = @restaurant.reservations.ransack(params[:q])
    reservations_query = @q.result.includes(:table, :business_period)
    
    # 處理日期篩選，預設顯示今天的訂位
    if params[:show_all] == 'true'
      # 顯示全部訂位，不進行日期篩選
      @filter_date = nil
      @show_all = true
    elsif params[:date_filter].present?
      @filter_date = Date.parse(params[:date_filter])
      reservations_query = reservations_query.where(
        reservation_datetime: @filter_date.beginning_of_day..@filter_date.end_of_day
      )
      @show_all = false
    else
      # 預設顯示今天的訂位
      @filter_date = Date.current
      reservations_query = reservations_query.where(
        reservation_datetime: @filter_date.beginning_of_day..@filter_date.end_of_day
      )
      @show_all = false
    end
    
    @reservations = reservations_query.order(reservation_datetime: :desc)
                                     .page(params[:page])
                                     .per(20)

    respond_to do |format|
      format.html
      format.turbo_stream do
        render turbo_stream: turbo_stream.update("reservations-container", 
                                                 partial: "reservations_table", 
                                                 locals: { reservations: @reservations })
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

  def edit
  end

  def new
    @reservation = @restaurant.reservations.build
  end

  def create
    @reservation = @restaurant.reservations.build(reservation_params)
    
    # 處理時區問題 - 確保使用台北時區
    if params[:reservation][:reservation_datetime].present?
      @reservation.reservation_datetime = parse_time_in_timezone(params[:reservation][:reservation_datetime])
    end
    
    # 處理大人數和小孩數的自動調整
    if @reservation.adults_count.blank? && @reservation.children_count.blank?
      @reservation.adults_count = [@reservation.party_size - (@reservation.children_count || 0), 1].max
      @reservation.children_count ||= 0
    end
    
    # 設定預設狀態為已確認
    @reservation.status = :confirmed
    
    if @reservation.save
      # 嘗試自動分配桌位（如果沒有手動指定）
      unless @reservation.table_id.present?
        allocate_table_for_reservation(@reservation)
        @reservation.save  # 儲存桌位分配結果
      end
      respond_to do |format|
        format.html do
          redirect_to admin_restaurant_reservation_path(@restaurant, @reservation),
                      notice: '訂位建立成功'
        end
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.prepend('reservations-list',
                               partial: 'reservation_row',
                               locals: { reservation: @reservation }),
            turbo_stream.update('flash',
                               partial: 'shared/flash',
                               locals: { message: '訂位建立成功', type: 'success' })
          ]
        end
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('reservation_form',
                                                  partial: 'form',
                                                  locals: { reservation: @reservation })
        end
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
        if adults_count + children_count > new_party_size
          children_count = [new_party_size - adults_count, 0].max
        end
        
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
          redirect_to admin_restaurant_reservation_path(@restaurant, @reservation),
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
                                                  locals: { message: @reservation.errors.full_messages.join(', '), type: 'error' })
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
          render turbo_stream: turbo_stream.update("flash_messages", 
                                                  partial: "shared/flash", 
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
          render turbo_stream: turbo_stream.update("flash_messages", 
                                                  partial: "shared/flash", 
                                                  locals: { alert: "標記未出席失敗：#{@reservation.errors.full_messages.join(', ')}" })
        end
        format.json { render json: { status: 'error', message: '標記未出席失敗', errors: @reservation.errors.full_messages } }
      end
    end
  end

  def calendar
    @reservations = @restaurant.reservations
                              .where(reservation_datetime: 1.month.ago..1.month.from_now)
                              .includes(:table, :business_period)

    respond_to do |format|
      format.html
      format.json do
        events = @reservations.map do |reservation|
          {
            id: reservation.id,
            title: "#{reservation.customer_name} - #{reservation.party_size}人",
            start: reservation.reservation_datetime.iso8601,
            end: (reservation.reservation_datetime + 2.hours).iso8601,
            className: "status-#{reservation.status}",
            extendedProps: {
              customer_name: reservation.customer_name,
              customer_phone: reservation.customer_phone,
              party_size: reservation.party_size,
              status: reservation.status,
              table_number: reservation.table&.table_number
            }
          }
        end
        render json: events
      end
    end
  end

  def search
    @q = @restaurant.reservations.ransack(params[:q])
    @reservations = @q.result
                     .includes(:table, :business_period)
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
    if params[:restaurant_id].to_i > 0
      @restaurant = Restaurant.find(params[:restaurant_id])
    else
      @restaurant = Restaurant.find_by!(slug: params[:restaurant_id])
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_restaurants_path, alert: '找不到指定的餐廳'
  end

  def set_reservation
    @reservation = @restaurant.reservations.find(params[:id])
  end

  def set_form_data
    @business_periods = @restaurant.business_periods.active
    @available_tables = @restaurant.restaurant_tables.active.ordered
  end

  def reservation_params
    params.require(:reservation).permit(
      :customer_name, :customer_phone, :customer_email,
      :party_size, :adults_count, :children_count,
      :reservation_datetime, :status, :notes,
      :special_requests, :table_id,
      :business_period_id
    )
  end

  # 為訂位分配桌位
  def allocate_table_for_reservation(reservation)
    allocator = ReservationAllocatorService.new(reservation)
    allocated_table = allocator.allocate_table
    
    if allocated_table
      if allocated_table.is_a?(Array)
        # 併桌情況 - 創建 TableCombination
        combination = TableCombination.new(
          reservation: reservation,
          name: "併桌 #{allocated_table.map(&:table_number).join('+')}"
        )
        
        # 建立桌位關聯
        allocated_table.each do |table|
          combination.table_combination_tables.build(restaurant_table: table)
        end
        
        if combination.save
          Rails.logger.info "分配併桌給訂位 #{reservation.id}: #{allocated_table.map(&:table_number).join(', ')}"
          # 設定主桌位（用於相容性）
          reservation.table = allocated_table.first
        else
          Rails.logger.error "創建併桌組合失敗: #{combination.errors.full_messages.join(', ')}"
        end
      else
        # 單桌情況
        reservation.table = allocated_table
        Rails.logger.info "分配桌位 #{allocated_table.table_number} 給訂位 #{reservation.id}"
      end
    else
      Rails.logger.warn "無法為訂位 #{reservation.id} 找到合適的桌位"
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
        Rails.logger.warn "重新分配桌位失敗，原為併桌無法恢復"
      end
    end
    
    reservation.save
  end
end 