class CustomerCancellationsController < ApplicationController
  before_action :set_restaurant
  before_action :set_reservation

  # GET /restaurants/:slug/reservations/:token/cancel
  def show
    @can_cancel = @reservation.can_cancel_by_customer?
    @cancellation_deadline = @reservation.cancellation_deadline

    # 檢查是否有成功取消的通知
    @success_message = flash[:notice] if flash[:notice]&.include?('已成功取消')

    if @reservation.cancelled? || @reservation.no_show?
      @status_message = case @reservation.status
                        when 'cancelled'
                          '此訂位已被取消'
                        when 'no_show'
                          '此訂位已標記為未到'
                        end
    elsif @reservation.is_past?
      @status_message = '此訂位已完成'
    end
  end

  # POST /restaurants/:slug/reservations/:token/cancel
  def create
    unless @reservation.can_cancel_by_customer?
      @error_message = if @reservation.is_past?
                         '此訂位已過期，無法取消'
                       elsif @reservation.cancelled?
                         '此訂位已被取消'
                       else
                         '此訂位無法取消'
                       end

      render :show and return
    end

    cancellation_reason = params[:cancellation_reason]&.strip

    if @reservation.cancel_by_customer!(cancellation_reason)
      # 發送確認通知
      if @reservation.customer_email.present?
        # CustomerMailer.cancellation_confirmation(@reservation).deliver_later
      end

      if @reservation.customer_phone.present?
        # SmsService.new.send_cancellation_confirmation(@reservation)
      end

      Rails.logger.info "Customer cancelled reservation #{@reservation.id} for restaurant #{@restaurant.name}"

      # 跳轉到成功頁面，避免重複提交
      redirect_to restaurant_reservation_cancel_path(@restaurant.slug, @reservation.cancellation_token),
                  notice: '訂位已成功取消'
    else
      @error_message = '取消訂位失敗，請聯繫餐廳'
      render :show
    end
  end

  private

  def set_restaurant
    @restaurant = Restaurant.find_by!(slug: params[:slug])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: '找不到指定的餐廳'
  end

  def set_reservation
    @reservation = @restaurant.reservations.find_by!(cancellation_token: params[:token])
  rescue ActiveRecord::RecordNotFound
    redirect_to restaurant_public_path(@restaurant.slug), alert: '找不到指定的訂位記錄'
  end
end
