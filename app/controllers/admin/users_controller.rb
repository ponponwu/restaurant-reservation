class Admin::UsersController < AdminController
  before_action :set_user, only: [:show, :edit, :update, :destroy, :toggle_status]

  def index
    @users = User.active.includes(:restaurant)
    
    # 簡單搜尋功能
    if params[:search].present?
      @users = @users.search_by_name_or_email(params[:search])
    end
    
    @users = @users.page(params[:page]).per(10)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.generate_random_password

    if @user.save
      @generated_password = @user.password
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.prepend('users_list', partial: 'user_row', locals: { user: @user }),
            turbo_stream.update('user_form', partial: 'password_generated', locals: { user: @user, password: @generated_password }),
            turbo_stream.update('flash_messages', partial: 'shared/flash', locals: { message: '管理員建立成功', type: 'success' })
          ]
        end
        format.html { redirect_to admin_users_path, notice: '管理員建立成功' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('user_form', partial: 'form', locals: { user: @user })
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    if @user.update(user_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("user_#{@user.id}", partial: 'user_row', locals: { user: @user }),
            turbo_stream.update('flash_messages', partial: 'shared/flash', locals: { message: '管理員資料已更新', type: 'success' })
          ]
        end
        format.html { redirect_to admin_users_path, notice: '管理員資料已更新' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('user_form', partial: 'form', locals: { user: @user })
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @user.soft_delete!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("user_#{@user.id}"),
          turbo_stream.update('flash_messages', partial: 'shared/flash', locals: { message: '管理員已刪除', type: 'success' })
        ]
      end
      format.html { redirect_to admin_users_path, notice: '管理員已刪除' }
    end
  end

  def toggle_status
    @user.update!(active: !@user.active?)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("user_#{@user.id}", partial: 'user_row', locals: { user: @user })
      end
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :email, :role, :restaurant_id)
  end
end 