class Admin::BlacklistsController < AdminController
  before_action :set_current_restaurant
  before_action :set_blacklist, only: [:show, :edit, :update, :destroy, :toggle_active]

  def index
    @q = current_restaurant.blacklists.ransack(params[:q])
    @pagy, @blacklists = pagy(@q.result.recent)
    
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show
  end

  def new
    @blacklist = current_restaurant.blacklists.build
    
    # 如果從訂位頁面跳轉過來，預填客戶資訊
    if params[:customer_phone].present?
      @blacklist.customer_phone = params[:customer_phone]
      @blacklist.customer_name = params[:customer_name]
    end
  end

  def create
    @blacklist = current_restaurant.blacklists.build(blacklist_params)
    @blacklist.added_by_name = current_user.display_name
    
    if @blacklist.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.prepend('blacklists', 
                               partial: 'blacklist', 
                               locals: { blacklist: @blacklist }),
            turbo_stream.update('flash', 
                               partial: 'shared/flash', 
                               locals: { message: '黑名單新增成功' })
          ]
        end
        format.html { redirect_to admin_blacklists_path, notice: '黑名單新增成功' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('blacklist_form',
                                                  partial: 'form',
                                                  locals: { blacklist: @blacklist })
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    if @blacklist.update(blacklist_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("blacklist_#{@blacklist.id}", 
                                partial: 'blacklist', 
                                locals: { blacklist: @blacklist }),
            turbo_stream.update('flash', 
                               partial: 'shared/flash', 
                               locals: { message: '黑名單更新成功' })
          ]
        end
        format.html { redirect_to admin_blacklists_path, notice: '黑名單更新成功' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('blacklist_form',
                                                  partial: 'form',
                                                  locals: { blacklist: @blacklist })
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @blacklist.destroy
    
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("blacklist_#{@blacklist.id}"),
          turbo_stream.update('flash', 
                             partial: 'shared/flash', 
                             locals: { message: '黑名單已刪除' })
        ]
      end
      format.html { redirect_to admin_blacklists_path, notice: '黑名單已刪除' }
    end
  end

  def toggle_active
    if @blacklist.active?
      @blacklist.deactivate!
      message = '已停用黑名單'
    else
      @blacklist.activate!
      message = '已啟用黑名單'
    end
    
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("blacklist_#{@blacklist.id}", 
                              partial: 'blacklist', 
                              locals: { blacklist: @blacklist }),
          turbo_stream.update('flash', 
                             partial: 'shared/flash', 
                             locals: { message: message })
        ]
      end
      format.html { redirect_to admin_blacklists_path, notice: message }
    end
  end

  private

  def set_blacklist
    @blacklist = current_restaurant.blacklists.find(params[:id])
  end

  def blacklist_params
    params.require(:blacklist).permit(
      :customer_name, :customer_phone, :reason
    )
  end
end
