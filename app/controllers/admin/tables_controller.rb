class Admin::TablesController < AdminController
  before_action :set_restaurant
  before_action :check_restaurant_access
  before_action :set_table_group, only: [:create, :edit, :show, :update, :destroy, :update_status]
  before_action :set_table, only: [:show, :edit, :update, :destroy, :update_status, :toggle_active, :move_to_group]

  def index
    @table_groups = @restaurant.table_groups.active.ordered.includes(:restaurant_tables)
    @tables = @restaurant.restaurant_tables.active.ordered.includes(:table_group)
  end

  def show
  end

  def new
    @table_group = @restaurant.table_groups.find(params[:table_group_id]) if params[:table_group_id]
    @table = (@table_group || @restaurant).restaurant_tables.build(
      restaurant: @restaurant
    )
    @table.sort_order = @restaurant.restaurant_tables.maximum(:sort_order).to_i + 1
  end

  def create
    @table = @table_group.restaurant_tables.build(table_params)
    @table.restaurant = @restaurant
    
    # 確保設定正確的全域排序順序
    if @table.sort_order.blank? || @table.sort_order <= 0
      @table.sort_order = @restaurant.restaurant_tables.maximum(:sort_order).to_i + 1
    end

    if @table.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove('modal'),
            turbo_stream.update('flash_messages', partial: 'shared/flash', locals: { message: '桌位建立成功', type: 'success' }),
            # 只添加新的桌位行，而不是替換整個群組
            turbo_stream.after("group_#{@table.table_group.id}", 
                              partial: 'admin/table_groups/table_row', 
                              locals: { 
                                table: @table, 
                                table_group: @table.table_group, 
                                global_priorities: {} 
                              })
          ]
        end
        format.html { redirect_to admin_restaurant_table_groups_path(@restaurant), notice: '桌位建立成功' }
      end
    else
      # 優先使用 turbo_stream 回應，避免跳頁
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('modal', 
                                                  partial: 'new', 
                                                  locals: { table: @table })
        end
        format.html do
          # 如果是 turbo_frame 請求，渲染 modal 內容
          if turbo_frame_request?
            render 'new', layout: false
          else
            render :new, status: :unprocessable_entity
          end
        end
      end
    end
  end

  def edit
  end

  def update
    if @table.update(table_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove('modal'),
            turbo_stream.update('flash_messages', partial: 'shared/flash', locals: { message: '桌位更新成功', type: 'success' }),
            turbo_stream.replace("table_#{@table.id}", 
                                partial: 'admin/table_groups/table_row', 
                                locals: { 
                                  table: @table, 
                                  table_group: @table.table_group, 
                                  global_priorities: {} 
                                })
          ]
        end
        format.html { redirect_to admin_restaurant_table_groups_path(@restaurant), notice: '桌位更新成功' }
      end
    else
      # 優先使用 turbo_stream 回應，避免跳頁
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('modal', 
                                                  partial: 'edit', 
                                                  locals: { table: @table })
        end
        format.html do
          # 如果是 turbo_frame 請求，渲染 modal 內容
          if turbo_frame_request?
            render 'edit', layout: false
          else
            render :edit, status: :unprocessable_entity
          end
        end
      end
    end
  end

  def destroy
    if @table.reservations.any?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('flash_messages', 
                                                  partial: 'shared/flash', 
                                                  locals: { message: '無法刪除：此桌位有訂位記錄', type: 'error' })
        end
        format.html { redirect_to admin_restaurant_table_groups_path(@restaurant), alert: '無法刪除：此桌位有訂位記錄' }
      end
    else
      table_id = @table.id
      @table.destroy
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove("table_#{table_id}"),
            turbo_stream.update('flash_messages', 
                               partial: 'shared/flash', 
                               locals: { message: '桌位已刪除', type: 'success' })
          ]
        end
        format.html { redirect_to admin_restaurant_table_groups_path(@restaurant), notice: '桌位已刪除' }
      end
    end
  end

  def update_status
    if @table.update(status: params[:status])
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("table_#{@table.id}",
                                                  partial: 'table_card',
                                                  locals: { table: @table, restaurant: @restaurant, priority: @table.sort_order || 1 })
        end
        format.json { render json: { success: true } }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('flash_messages',
                                                  partial: 'shared/flash',
                                                  locals: { message: '狀態更新失敗', type: 'error' })
        end
        format.json { render json: { success: false, errors: @table.errors } }
      end
    end
  end

  def toggle_active
    @table.update(active: !@table.active)
    
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("table_#{@table.id}", 
                              partial: 'admin/table_groups/table_item', 
                              locals: { table: @table }),
          turbo_stream.update('flash_messages', 
                             partial: 'shared/flash', 
                             locals: { message: "桌位已#{@table.active? ? '啟用' : '停用'}", type: 'success' })
        ]
      end
      format.html { redirect_to admin_restaurant_table_groups_path(@restaurant) }
    end
  end

  def move_to_group
    old_group_id = @table.table_group_id
    new_group = @restaurant.table_groups.find(params[:table_group_id])
    
    ActiveRecord::Base.transaction do
      @table.update!(
        table_group: new_group,
        sort_order: RestaurantTable.next_sort_order_in_group(new_group)
      )
      
      # 重新計算所有桌位的全域 sort_order
      RestaurantTable.recalculate_global_sort_order!(@restaurant)
    end
    
    render json: { 
      success: true, 
      message: "桌位已移動到 #{new_group.name}",
      old_group_id: old_group_id,
      new_group_id: new_group.id
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { 
      success: false, 
      message: e.record.errors.full_messages.join(', ') 
    }, status: :unprocessable_entity
  end

  private

  def set_restaurant
    if current_user.super_admin?
      @restaurant = Restaurant.find_by!(slug: params[:restaurant_id])
    else
      # 餐廳管理員和員工只能存取自己的餐廳
      @restaurant = Restaurant.where(id: current_user.restaurant_id).find_by!(slug: params[:restaurant_id])
    end
  end

  def check_restaurant_access
    unless current_user.can_manage_restaurant?(@restaurant)
      redirect_to admin_restaurants_path, alert: '您沒有權限存取此餐廳的桌位管理'
    end
  end

  def set_table_group
    @table_group = @restaurant.table_groups.find(params[:table_group_id]) if params[:table_group_id]
  end

  def set_table
    if @table_group
      @table = @table_group.restaurant_tables.find(params[:id])
    else
      @table = @restaurant.restaurant_tables.find(params[:id])
    end
  end

  def table_params
    params.require(:restaurant_table).permit(:table_number, :capacity, :min_capacity, :max_capacity, 
                                 :table_type, :status, :sort_order, :metadata, :can_combine)
  end
end 