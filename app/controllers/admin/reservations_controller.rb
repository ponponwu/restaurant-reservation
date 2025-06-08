class Admin::ReservationsController < Admin::BaseController
  before_action :set_restaurant
  before_action :set_reservation, only: [:show, :edit, :update, :destroy, :confirm, :cancel, :seat, :complete, :no_show]

  def index
    @q = @restaurant.reservations.ransack(params[:q])
    reservations_query = @q.result.includes(:table, :business_period)
    
    # 處理日期篩選
    if params[:date_filter].present?
      filter_date = Date.parse(params[:date_filter])
      reservations_query = reservations_query.where(
        reservation_datetime: filter_date.beginning_of_day..filter_date.end_of_day
      )
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

  def update
    if @reservation.update(reservation_params)
      redirect_to admin_restaurant_reservation_path(@restaurant, @reservation),
                  notice: '訂位已更新成功'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @reservation.destroy!
    redirect_to admin_restaurant_reservations_path(@restaurant),
                notice: '訂位已刪除'
  end

  # 狀態管理方法
  def confirm
    if @reservation.update(status: :confirmed)
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), notice: '訂位已確認' }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("reservation_#{@reservation.id}", 
                               partial: "reservation_row", 
                               locals: { reservation: @reservation }),
            turbo_stream.update("flash", 
                               partial: "shared/flash", 
                               locals: { notice: "訂位已確認" })
          ]
        end
        format.json { render json: { status: 'success', message: '訂位已確認' } }
      end
    else
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), alert: '確認訂位失敗' }
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash", 
                                                  partial: "shared/flash", 
                                                  locals: { alert: "確認訂位失敗：#{@reservation.errors.full_messages.join(', ')}" })
        end
        format.json { render json: { status: 'error', message: '確認訂位失敗', errors: @reservation.errors.full_messages } }
      end
    end
  end

  def cancel
    if @reservation.update(status: :cancelled)
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), notice: '訂位已取消' }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("reservation_#{@reservation.id}", 
                               partial: "reservation_row", 
                               locals: { reservation: @reservation }),
            turbo_stream.update("flash", 
                               partial: "shared/flash", 
                               locals: { notice: "訂位已取消" })
          ]
        end
        format.json { render json: { status: 'success', message: '訂位已取消' } }
      end
    else
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), alert: '取消訂位失敗' }
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash", 
                                                  partial: "shared/flash", 
                                                  locals: { alert: "取消訂位失敗：#{@reservation.errors.full_messages.join(', ')}" })
        end
        format.json { render json: { status: 'error', message: '取消訂位失敗', errors: @reservation.errors.full_messages } }
      end
    end
  end

  def seat
    if @reservation.update(status: :seated)
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), notice: '已安排就座' }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("reservation_#{@reservation.id}", 
                               partial: "reservation_row", 
                               locals: { reservation: @reservation }),
            turbo_stream.update("flash", 
                               partial: "shared/flash", 
                               locals: { notice: "已安排就座" })
          ]
        end
        format.json { render json: { status: 'success', message: '已安排就座' } }
      end
    else
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), alert: '安排就座失敗' }
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash", 
                                                  partial: "shared/flash", 
                                                  locals: { alert: "安排就座失敗：#{@reservation.errors.full_messages.join(', ')}" })
        end
        format.json { render json: { status: 'error', message: '安排就座失敗', errors: @reservation.errors.full_messages } }
      end
    end
  end

  def complete
    if @reservation.update(status: :completed)
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), notice: '訂位已完成' }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("reservation_#{@reservation.id}", 
                               partial: "reservation_row", 
                               locals: { reservation: @reservation }),
            turbo_stream.update("flash", 
                               partial: "shared/flash", 
                               locals: { notice: "訂位已完成" })
          ]
        end
        format.json { render json: { status: 'success', message: '訂位已完成' } }
      end
    else
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), alert: '完成訂位失敗' }
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash", 
                                                  partial: "shared/flash", 
                                                  locals: { alert: "完成訂位失敗：#{@reservation.errors.full_messages.join(', ')}" })
        end
        format.json { render json: { status: 'error', message: '完成訂位失敗', errors: @reservation.errors.full_messages } }
      end
    end
  end

  def no_show
    if @reservation.update(status: :no_show)
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), notice: '已標記為未出席' }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("reservation_#{@reservation.id}", 
                               partial: "reservation_row", 
                               locals: { reservation: @reservation }),
            turbo_stream.update("flash", 
                               partial: "shared/flash", 
                               locals: { notice: "已標記為未出席" })
          ]
        end
        format.json { render json: { status: 'success', message: '已標記為未出席' } }
      end
    else
      respond_to do |format|
        format.html { redirect_to admin_restaurant_reservations_path(@restaurant), alert: '標記未出席失敗' }
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash", 
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

  def reservation_params
    params.require(:reservation).permit(
      :customer_name, :customer_phone, :customer_email,
      :party_size, :adults_count, :children_count,
      :reservation_datetime, :status, :notes,
      :special_requests, :table_id,
      :business_period_id
    )
  end
end 