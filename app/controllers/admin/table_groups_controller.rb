class Admin::TableGroupsController < AdminController
  before_action :set_restaurant
  before_action :set_table_group, only: %i[show edit update destroy reorder_tables toggle_active]

  def index
    @table_groups = @restaurant.table_groups.active.ordered
      .includes(restaurant_tables: :table_group)

    # 預計算全域優先順序，避免 N+1 查詢
    @global_priorities = calculate_global_priorities(@table_groups)
  end

  def show
    @tables = @table_group.restaurant_tables.active.ordered
  end

  def new
    @table_group = @restaurant.table_groups.build(
      sort_order: TableGroup.next_sort_order(@restaurant)
    )
  end

  def edit; end

  def create
    @table_group = @restaurant.table_groups.build(table_group_params)

    if @table_group.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove('modal'),
            turbo_stream.update('flash_messages', partial: 'shared/flash',
                                                  locals: { message: '桌位群組建立成功', type: 'success' }),
            turbo_stream.append('table-groups-tbody', partial: 'admin/table_groups/table_group_row',
                                                      locals: { table_group: @table_group, global_priorities: {} })
          ]
        end
        format.html { redirect_to admin_restaurant_table_groups_path(@restaurant), notice: '桌位群組建立成功' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('modal',
                                                   partial: 'new',
                                                   locals: { table_group: @table_group })
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def update
    if @table_group.update(table_group_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove('modal'),
            turbo_stream.update('flash_messages', partial: 'shared/flash',
                                                  locals: { message: '桌位群組更新成功', type: 'success' }),
            turbo_stream.replace("group_#{@table_group.id}", partial: 'admin/table_groups/table_group_row',
                                                             locals: { table_group: @table_group, global_priorities: {} })
          ]
        end
        format.html { redirect_to admin_restaurant_table_groups_path(@restaurant), notice: '桌位群組更新成功' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('modal',
                                                   partial: 'edit',
                                                   locals: { table_group: @table_group })
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    if @table_group.restaurant_tables.any?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('flash_messages',
                                                   partial: 'shared/flash',
                                                   locals: { message: '無法刪除：此群組內還有桌位', type: 'error' })
        end
        format.html { redirect_to admin_restaurant_table_groups_path(@restaurant), alert: '無法刪除：此群組內還有桌位' }
      end
    else
      @table_group.destroy
      respond_to do |format|
        format.turbo_stream do
          redirect_to admin_restaurant_table_groups_path(@restaurant), notice: '桌位群組已刪除'
        end
        format.html { redirect_to admin_restaurant_table_groups_path(@restaurant), notice: '桌位群組已刪除' }
      end
    end
  end

  def reorder
    ordered_ids = params[:ordered_ids]

    if ordered_ids.present?
      ActiveRecord::Base.transaction do
        # 更新群組順序
        ordered_ids.each_with_index do |group_id, index|
          table_group = @restaurant.table_groups.find(group_id)
          table_group.update!(sort_order: index + 1)
        end

        # 重新計算所有桌位的全域 sort_order
        RestaurantTable.recalculate_global_sort_order!(@restaurant)
      end

      render json: { success: true, message: '群組順序已更新' }
    else
      render json: { success: false, message: '無效的排序資料' }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def reorder_tables
    ordered_ids = params[:ordered_ids]

    if ordered_ids.present?
      ActiveRecord::Base.transaction do
        # 更新群組內桌位順序
        ordered_ids.each_with_index do |table_id, index|
          table = @table_group.restaurant_tables.find(table_id)
          table.update!(sort_order: index + 1)
        end

        # 重新計算所有桌位的全域 sort_order
        RestaurantTable.recalculate_global_sort_order!(@restaurant)
      end

      render json: {
        success: true,
        message: '桌位排序已更新'
      }
    else
      render json: {
        success: false,
        message: '無效的排序資料'
      }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      success: false,
      message: e.record.errors.full_messages.join(', ')
    }, status: :unprocessable_entity
  end

  def toggle_active
    @table_group.update(active: !@table_group.active)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("table_group_#{@table_group.id}",
                               partial: 'table_group_card',
                               locals: { table_group: @table_group }),
          turbo_stream.update('flash_messages',
                              partial: 'shared/flash',
                              locals: { message: "桌位群組已#{@table_group.active? ? '啟用' : '停用'}", type: 'success' })
        ]
      end
      format.html { redirect_to admin_restaurant_table_groups_path(@restaurant) }
    end
  end

  private

  def set_restaurant
    @restaurant = Restaurant.find_by!(slug: params[:restaurant_id])

    # super_admin 和 manager 可以管理所有餐廳
    return if current_user.super_admin? || current_user.manager?

    redirect_to admin_restaurants_path, alert: '您沒有權限管理此餐廳'
  end

  def set_table_group
    @table_group = @restaurant.table_groups.find(params[:id])
  end

  def table_group_params
    params.require(:table_group).permit(:name, :description, :sort_order)
  end

  def calculate_global_priorities(table_groups)
    priorities = {}
    global_priority = 1

    # 使用已預載入的關聯，避免額外的資料庫查詢
    table_groups.each do |table_group|
      # 從已預載入的關聯中篩選和排序桌位
      active_tables = table_group.restaurant_tables
        .select(&:active?)
        .sort_by(&:sort_order)

      active_tables.each do |table|
        priorities[table.id] = global_priority
        global_priority += 1
      end
    end

    priorities
  end
end
