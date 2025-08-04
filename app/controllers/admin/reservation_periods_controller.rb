class Admin::ReservationPeriodsController < AdminController
  before_action :set_restaurant
  before_action :check_restaurant_access
  before_action :set_reservation_period, only: %i[show edit update destroy toggle_active]

  def index
    @reservation_periods = @restaurant.reservation_periods.active.includes(:reservation_slots).ordered
    @new_reservation_period = @restaurant.reservation_periods.build

    respond_to do |format|
      format.html do
        # 如果是 AJAX 請求，不使用 layout
        render layout: false if request.xhr?
      end
      format.turbo_stream
    end
  end

  def show; end

  def new
    @reservation_period = @restaurant.reservation_periods.build

    # 如果有 weekday 參數，預設選中該天
    if params[:weekday].present?
      @reservation_period.weekday = params[:weekday].to_i
      @preset_weekday = params[:weekday].to_i
    end

    respond_to do |format|
      format.html { render layout: false if request.xhr? }
      format.turbo_stream
    end
  end

  def edit
    respond_to do |format|
      format.html do
        if request.xhr?
          # AJAX 請求，渲染 modal 表單
          render partial: 'form_modal', locals: { reservation_period: @reservation_period }, layout: false
        else
          # 一般 HTML 請求，不使用 layout
          render layout: false
        end
      end
      format.turbo_stream
    end
  end

  def create
    @reservation_period = @restaurant.reservation_periods.build(reservation_period_params)

    respond_to do |format|
      if @reservation_period.save
        format.turbo_stream do
          # 檢查是否來自設定頁面（modal）
          if request.referer&.include?('restaurant_settings')
            # 檢查是否有 weekday 參數，來自 weekday 的新增請求
            if @reservation_period.weekday.present?
              # 來自特定 weekday 的新增，更新該 weekday 的餐期列表
              periods = @restaurant.reservation_periods.for_weekday(@reservation_period.weekday).default_weekly.active
              render turbo_stream: [
                turbo_stream.update("weekday_#{@reservation_period.weekday}_periods",
                                    partial: 'admin/restaurant_settings/restaurant_settings/weekday_periods_list',
                                    locals: { weekday: @reservation_period.weekday, periods: periods,
                                              restaurant: @restaurant }),
                turbo_stream.update('flash_messages',
                                    partial: 'shared/flash',
                                    locals: { message: '營業時段建立成功', type: 'success' }),
                turbo_stream.append_all('body',
                                        "<script>document.dispatchEvent(new CustomEvent('close-modal'))</script>")
              ]
            else
              # 來自設定頁面的 modal，刷新整個業務時段列表
              @reservation_periods = @restaurant.reservation_periods.active.includes(:reservation_slots).ordered
              render turbo_stream: [
                turbo_stream.update('reservation_periods_list',
                                    partial: 'admin/restaurant_settings/restaurant_settings/reservation_periods_list',
                                    locals: { reservation_periods: @reservation_periods, restaurant: @restaurant }),
                turbo_stream.update('flash_messages',
                                    partial: 'shared/flash',
                                    locals: { message: '營業時段建立成功', type: 'success' }),
                turbo_stream.append_all('body',
                                        "<script>document.dispatchEvent(new CustomEvent('close-modal'))</script>")
              ]
            end
          else
            # 來自一般管理頁面
            render turbo_stream: [
              turbo_stream.append('reservation_periods_list',
                                  partial: 'reservation_period_row',
                                  locals: { reservation_period: @reservation_period }),
              turbo_stream.update('flash_messages',
                                  partial: 'shared/flash',
                                  locals: { message: '營業時段建立成功', type: 'success' }),
              turbo_stream.update('new_reservation_period_form',
                                  partial: 'form',
                                  locals: { reservation_period: @restaurant.reservation_periods.build })
            ]
          end
        end
        format.html do
          # 檢查是否來自 modal（通過 openRemote）
          if request.xhr? && request.referer&.include?('restaurant_settings')
            # 返回 JavaScript 來關閉 modal 並刷新頁面
            render html: "<script>
              document.dispatchEvent(new CustomEvent('close-modal'));
              window.location.reload();
            </script>".html_safe, layout: false
            return
          else
            # 一般 HTML 請求
            redirect_to admin_restaurant_reservation_periods_path(@restaurant), notice: '營業時段建立成功'
            return
          end
        end
      else
        format.turbo_stream do
          # 如果有驗證錯誤，重新渲染 modal 表單
          if request.referer&.include?('restaurant_settings')
            render turbo_stream: turbo_stream.update('modal-content',
                                                     partial: 'form_modal',
                                                     locals: { reservation_period: @reservation_period })
          else
            render turbo_stream: turbo_stream.update('new_reservation_period_form',
                                                     partial: 'form',
                                                     locals: { reservation_period: @reservation_period })
          end
        end
        format.html do
          # 檢查是否來自 modal（通過 openRemote）
          if request.xhr? && request.referer&.include?('restaurant_settings')
            # 重新渲染 modal 表單顯示錯誤
            render partial: 'form_modal', locals: { reservation_period: @reservation_period }, layout: false,
                   status: :unprocessable_entity
            return
          else
            # 一般 HTML 請求，回到 new 頁面
            render :new, status: :unprocessable_entity
            return
          end
        end
      end
    end
  end

  def update
    respond_to do |format|
      if @reservation_period.update(reservation_period_params)
        format.turbo_stream do
          # 檢查是否來自設定頁面（modal）
          if request.referer&.include?('restaurant_settings')
            # 檢查是否來自特定 weekday，更新該 weekday 的餐期列表
            if @reservation_period.weekday.present?
              periods = @restaurant.reservation_periods.for_weekday(@reservation_period.weekday).default_weekly.active
              render turbo_stream: [
                turbo_stream.update("weekday_#{@reservation_period.weekday}_periods",
                                    partial: 'admin/restaurant_settings/restaurant_settings/weekday_periods_list',
                                    locals: { weekday: @reservation_period.weekday, periods: periods,
                                              restaurant: @restaurant }),
                turbo_stream.update('flash_messages',
                                    partial: 'shared/flash',
                                    locals: { message: '營業時段更新成功', type: 'success' }),
                turbo_stream.append_all('body',
                                        "<script>document.dispatchEvent(new CustomEvent('close-modal'))</script>")
              ]
            else
              # 來自設定頁面的 modal，刷新整個業務時段列表
              @reservation_periods = @restaurant.reservation_periods.active.includes(:reservation_slots).ordered
              render turbo_stream: [
                turbo_stream.update('reservation_periods_list',
                                    partial: 'admin/restaurant_settings/restaurant_settings/reservation_periods_list',
                                    locals: { reservation_periods: @reservation_periods, restaurant: @restaurant }),
                turbo_stream.update('flash_messages',
                                    partial: 'shared/flash',
                                    locals: { message: '營業時段更新成功', type: 'success' }),
                turbo_stream.append_all('body',
                                        "<script>document.dispatchEvent(new CustomEvent('close-modal'))</script>")
              ]
            end
          else
            # 來自一般管理頁面
            render turbo_stream: [
              turbo_stream.replace("reservation_period_#{@reservation_period.id}",
                                   partial: 'reservation_period_row',
                                   locals: { reservation_period: @reservation_period }),
              turbo_stream.update('flash_messages',
                                  partial: 'shared/flash',
                                  locals: { message: '營業時段更新成功', type: 'success' }),
              turbo_stream.update('modal', '')
            ]
          end
        end
        format.html do
          # 檢查是否來自 modal（通過 openRemote）
          if request.xhr? && request.referer&.include?('restaurant_settings')
            # 返回 JavaScript 來關閉 modal 並刷新頁面
            render html: "<script>
              document.dispatchEvent(new CustomEvent('close-modal'));
              window.location.reload();
            </script>".html_safe, layout: false
            return
          else
            # 一般 HTML 請求
            redirect_to admin_restaurant_reservation_periods_path(@restaurant), notice: '營業時段更新成功'
            return
          end
        end
      else
        format.turbo_stream do
          # 如果有驗證錯誤，重新渲染 modal 表單
          if request.referer&.include?('restaurant_settings')
            render turbo_stream: turbo_stream.update('modal-content',
                                                     partial: 'form_modal',
                                                     locals: { reservation_period: @reservation_period })
          else
            render turbo_stream: turbo_stream.update('modal',
                                                     partial: 'edit',
                                                     locals: { reservation_period: @reservation_period })
          end
        end
        format.html do
          # 檢查是否來自 modal（通過 openRemote）
          if request.xhr? && request.referer&.include?('restaurant_settings')
            # 重新渲染 modal 表單顯示錯誤
            render partial: 'form_modal', locals: { reservation_period: @reservation_period }, layout: false,
                   status: :unprocessable_entity
            return
          else
            # 一般 HTML 請求，回到 edit 頁面
            render :edit, status: :unprocessable_entity
            return
          end
        end
      end
    end
  end

  def destroy
    weekday = @reservation_period.weekday
    @reservation_period.destroy

    respond_to do |format|
      format.turbo_stream do
        # 檢查是否來自設定頁面，且有 weekday 資料
        if request.referer&.include?('restaurant_settings') && weekday.present?
          # 更新對應的 weekday 餐期列表
          periods = @restaurant.reservation_periods.for_weekday(weekday).default_weekly.active
          render turbo_stream: [
            turbo_stream.update("weekday_#{weekday}_periods",
                                partial: 'admin/restaurant_settings/restaurant_settings/weekday_periods_list',
                                locals: { weekday: weekday, periods: periods, restaurant: @restaurant }),
            turbo_stream.update('flash_messages',
                                partial: 'shared/flash',
                                locals: { message: '營業時段已刪除', type: 'success' })
          ]
        else
          # 一般的刪除操作
          render turbo_stream: [
            turbo_stream.remove("reservation_period_#{@reservation_period.id}"),
            turbo_stream.update('flash_messages',
                                partial: 'shared/flash',
                                locals: { message: '營業時段已刪除', type: 'success' })
          ]
        end
      end
      format.html { redirect_to admin_restaurant_reservation_periods_path(@restaurant), notice: '營業時段已刪除' }
    end
  end

  def toggle_active
    @reservation_period.update!(active: !@reservation_period.active?)

    respond_to do |format|
      format.turbo_stream do
        # 檢查是否來自設定頁面
        if request.referer&.include?('restaurant_settings')
          # 檢查是否來自特定 weekday，更新該 weekday 的餐期列表
          if @reservation_period.weekday.present?
            periods = @restaurant.reservation_periods.for_weekday(@reservation_period.weekday).default_weekly.active
            render turbo_stream: [
              turbo_stream.update("weekday_#{@reservation_period.weekday}_periods",
                                  partial: 'admin/restaurant_settings/restaurant_settings/weekday_periods_list',
                                  locals: { weekday: @reservation_period.weekday, periods: periods,
                                            restaurant: @restaurant }),
              turbo_stream.update('flash_messages',
                                  partial: 'shared/flash',
                                  locals: { message: "營業時段已#{@reservation_period.active? ? '啟用' : '停用'}",
                                            type: 'success' })
            ]
          else
            # 來自設定頁面，重新載入整個頁面內容或只更新狀態
            render turbo_stream: [
              turbo_stream.update('flash_messages',
                                  partial: 'shared/flash',
                                  locals: { message: "營業時段已#{@reservation_period.active? ? '啟用' : '停用'}",
                                            type: 'success' }),
              turbo_stream.replace("reservation_period_#{@reservation_period.id}",
                                   partial: 'admin/restaurant_settings/restaurant_settings/reservation_period_item',
                                   locals: { period: @reservation_period, restaurant: @restaurant })
            ]
          end
        else
          # 來自一般管理頁面，使用原本的 partial
          render turbo_stream: [
            turbo_stream.replace("reservation_period_#{@reservation_period.id}",
                                 partial: 'reservation_period_row',
                                 locals: { reservation_period: @reservation_period }),
            turbo_stream.update('flash_messages',
                                partial: 'shared/flash',
                                locals: { message: "營業時段已#{@reservation_period.active? ? '啟用' : '停用'}",
                                          type: 'success' })
          ]
        end
      end
      format.html { redirect_to admin_restaurant_reservation_periods_path(@restaurant) }
    end
  end

  # 新增：編輯特定星期幾的時段
  def edit_day
    @weekday = params[:weekday].to_i
    @periods = @restaurant.reservation_periods.for_weekday(@weekday).default_weekly.active
    # 移除 operation_mode 邏輯，簡化為直接根據現有時段推斷模式
    @current_mode = determine_current_mode(@periods)

    respond_to do |format|
      format.html { render partial: 'edit_day_modal', layout: false }
    end
  end

  # 新增：更新特定星期幾的時段
  def update_day
    weekday = params[:weekday].to_i
    mode = params[:mode] || params[:operation_mode] # 支援舊的參數名稱
    periods_params = params[:periods] || []

    ActiveRecord::Base.transaction do
      # 刪除該星期幾現有的預設時段
      @restaurant.reservation_periods.for_weekday(weekday).default_weekly.destroy_all

      if mode == 'twenty_four_hours'
        # 24小時營業：創建一個24小時時段
        @restaurant.reservation_periods.create!(
          name: '24小時營業',
          start_time: Time.parse('00:00'),
          end_time: Time.parse('23:59'),
          weekday: weekday,
          reservation_interval_minutes: 60
        )
      elsif mode == 'custom_hours' || mode.blank?
        # 自訂時段：創建多個時段（如果沒有指定模式，預設為自訂時段）
        periods_params.each do |period_param|
          @restaurant.reservation_periods.create!(
            name: period_param[:name] || '自訂時段',
            start_time: Time.parse(period_param[:start_time]),
            end_time: Time.parse(period_param[:end_time]),
            weekday: weekday,
            reservation_interval_minutes: period_param[:interval].to_i
          )
        end
      end
    end

    render json: { success: true }
  rescue StandardError => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  # 新增：停用特定星期幾
  def disable_day
    weekday = params[:weekday].to_i

    ActiveRecord::Base.transaction do
      # 將該星期幾的時段設為關閉
      existing_periods = @restaurant.reservation_periods.for_weekday(weekday).default_weekly

      existing_periods.destroy_all if existing_periods.any?

      # 創建一個關閉狀態的時段
      @restaurant.reservation_periods.create!(
        name: '不開放',
        start_time: Time.parse('12:00'),
        end_time: Time.parse('13:00'),
        weekday: weekday,
        reservation_interval_minutes: 30,
        active: false
      )
    end

    render json: { success: true }
  rescue StandardError => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def set_restaurant
    @restaurant = if current_user.super_admin?
                    Restaurant.find_by!(slug: params[:restaurant_id])
                  else
                    # 餐廳管理員和員工只能存取自己的餐廳
                    unless current_user.restaurant_id.present?
                      raise ActiveRecord::RecordNotFound, 'User has no restaurant association'
                    end

                    Restaurant.where(id: current_user.restaurant_id).find_by!(slug: params[:restaurant_id])

                    # 如果用戶沒有餐廳關聯，直接拋出記錄未找到錯誤

                  end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "Restaurant access denied: #{e.message} for user #{current_user.id}"
    redirect_to admin_restaurants_path, alert: '您沒有權限存取此餐廳的營業時段管理'
  end

  def set_reservation_period
    @reservation_period = @restaurant.reservation_periods.find(params[:id])
  end

  def reservation_period_params
    permitted_params = params.require(:reservation_period).permit(
      :name, :display_name, :start_time, :end_time, :weekday, :date,
      :reservation_interval_minutes
    )

    # 確保時間參數使用正確的時區
    if permitted_params[:start_time].present?
      permitted_params[:start_time] = parse_time_in_timezone(permitted_params[:start_time])
    end

    if permitted_params[:end_time].present?
      permitted_params[:end_time] = parse_time_in_timezone(permitted_params[:end_time])
    end

    permitted_params
  end

  def parse_time_in_timezone(time_string)
    # 如果是 HH:MM 格式，添加日期部分並使用正確時區解析
    if time_string.match?(/^\d{2}:\d{2}$/)
      Time.zone.parse("2000-01-01 #{time_string}")
    else
      # 如果已經包含日期，直接解析
      Time.zone.parse(time_string)
    end
  rescue ArgumentError
    # 如果解析失敗，回傳原始值讓 Rails 處理驗證錯誤
    time_string
  end

  def determine_current_mode(periods)
    return 'custom_hours' if periods.empty?

    # 如果有一個時段是 00:00-23:59，判斷為 24 小時營業
    if periods.size == 1 &&
       periods.first.start_time.strftime('%H:%M') == '00:00' &&
       periods.first.end_time.strftime('%H:%M') == '23:59'
      'twenty_four_hours'
    elsif periods.any? && periods.all?(&:active?)
      'custom_hours'
    else
      'closed'
    end
  end
end
