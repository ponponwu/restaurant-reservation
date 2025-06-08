# Phase 2: 管理員功能實作

## 目標

完成管理員的 CRUD 功能，包含即時搜尋、狀態切換等 Hotwire 互動功能。

## 前置條件

-   Phase 1 已完成（Rails 基礎設定）
-   User 模型已建立
-   Devise 已設定完成

## 任務清單

### 1. 完善 User 模型

#### 1.1 User 模型設定

```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :restaurant, optional: true

  validates :first_name, presence: true, length: { maximum: 50 }
  validates :last_name, presence: true, length: { maximum: 50 }
  validates :role, inclusion: { in: %w[super_admin admin] }

  enum role: { admin: 0, super_admin: 1 }

  scope :active, -> { where(active: true, deleted_at: nil) }
  scope :search_by_name_or_email, ->(term) {
    where("first_name ILIKE ? OR last_name ILIKE ? OR email ILIKE ?",
          "%#{term}%", "%#{term}%", "%#{term}%")
  }

  def full_name
    "#{first_name} #{last_name}"
  end

  def soft_delete!
    update!(active: false, deleted_at: Time.current)
  end

  def generate_random_password
    self.password = SecureRandom.hex(8)
    self.password_confirmation = password
  end
end
```

#### 1.2 建立 CanCanCan Ability

```ruby
# app/models/ability.rb
class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new

    if user.super_admin?
      can :manage, :all
    elsif user.admin?
      can :read, User, id: user.id  # 只能看自己
      can :update, User, id: user.id  # 只能改自己
      # 其他餐廳相關權限...
    end
  end
end
```

### 2. 建立管理員控制器

#### 2.1 Admin::UsersController

```ruby
# app/controllers/admin/users_controller.rb
class Admin::UsersController < AdminController
  before_action :set_user, only: [:show, :edit, :update, :destroy, :toggle_status]

  def index
    @q = User.active.ransack(params[:q])
    @users = @q.result.includes(:restaurant).page(params[:page]).per(10)

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
```

#### 2.2 AdminController 基礎類別

```ruby
# app/controllers/admin_controller.rb
class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin_access

  private

  def ensure_admin_access
    redirect_to root_path unless current_user&.super_admin?
  end
end
```

### 3. 建立視圖檔案

#### 3.1 管理員列表頁面

```erb
<!-- app/views/admin/users/index.html.erb -->
<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <div class="sm:flex sm:items-center">
    <div class="sm:flex-auto">
      <h1 class="text-2xl font-semibold text-gray-900">管理員管理</h1>
      <p class="mt-2 text-sm text-gray-700">管理系統內所有管理員帳戶</p>
    </div>
    <div class="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
      <%= link_to new_admin_user_path,
          class: "inline-flex items-center justify-center rounded-md border border-transparent bg-blue-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 sm:w-auto" do %>
        新增管理員
      <% end %>
    </div>
  </div>

  <!-- 搜尋區域 -->
  <%= turbo_frame_tag "search_form", class: "mt-6" do %>
    <%= search_form_for @q, url: admin_users_path, local: false,
        data: { turbo_frame: "users_table", turbo_action: "advance" },
        class: "max-w-md" do |f| %>
      <div class="flex rounded-md shadow-sm">
        <%= f.search_field :first_name_or_last_name_or_email_cont,
            placeholder: "搜尋姓名或電子郵件...",
            class: "flex-1 min-w-0 block w-full px-3 py-2 rounded-none rounded-l-md border-gray-300 focus:ring-blue-500 focus:border-blue-500 sm:text-sm" %>
        <%= f.submit "搜尋",
            class: "inline-flex items-center px-3 py-2 border border-l-0 border-gray-300 rounded-r-md bg-gray-50 text-gray-500 text-sm hover:bg-gray-100" %>
      </div>
    <% end %>
  <% end %>

  <!-- 表格區域 -->
  <%= turbo_frame_tag "users_table", class: "mt-8 flex flex-col" do %>
    <div class="-my-2 -mx-4 overflow-x-auto sm:-mx-6 lg:-mx-8">
      <div class="inline-block min-w-full py-2 align-middle md:px-6 lg:px-8">
        <div class="overflow-hidden shadow ring-1 ring-black ring-opacity-5 md:rounded-lg">
          <table class="min-w-full divide-y divide-gray-300">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">姓名</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">電子郵件</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">角色</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">所屬餐廳</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">狀態</th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wide">操作</th>
              </tr>
            </thead>
            <tbody id="users_list" class="bg-white divide-y divide-gray-200">
              <% @users.each do |user| %>
                <%= render 'user_row', user: user %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- 分頁 -->
    <div class="mt-4">
      <%= paginate @users, theme: 'twitter_bootstrap_4' %>
    </div>
  <% end %>
</div>

<!-- Flash 訊息區域 -->
<div id="flash_messages" class="fixed top-4 right-4 z-50">
  <%= render 'shared/flash' if notice || alert %>
</div>
```

#### 3.2 使用者列表項目

```erb
<!-- app/views/admin/users/_user_row.html.erb -->
<tr id="user_<%= user.id %>" class="hover:bg-gray-50">
  <td class="whitespace-nowrap px-6 py-4 text-sm">
    <div class="flex items-center">
      <div>
        <div class="text-sm font-medium text-gray-900"><%= user.full_name %></div>
      </div>
    </div>
  </td>
  <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">
    <%= user.email %>
  </td>
  <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">
    <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full
                 <%= user.super_admin? ? 'bg-purple-100 text-purple-800' : 'bg-blue-100 text-blue-800' %>">
      <%= user.super_admin? ? 'Super Admin' : '管理員' %>
    </span>
  </td>
  <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">
    <%= user.restaurant&.name || '-' %>
  </td>
  <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">
    <%= button_to toggle_status_admin_user_path(user),
        method: :patch, remote: true,
        class: "inline-flex px-2 py-1 text-xs font-semibold rounded-full border-0
                #{user.active? ? 'bg-green-100 text-green-800 hover:bg-green-200' : 'bg-red-100 text-red-800 hover:bg-red-200'}" do %>
      <%= user.active? ? '啟用中' : '已停用' %>
    <% end %>
  </td>
  <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-6">
    <%= link_to edit_admin_user_path(user), class: "text-blue-600 hover:text-blue-900 mr-4" do %>
      編輯
    <% end %>
    <%= button_to admin_user_path(user), method: :delete,
        data: {
          controller: "confirmation",
          confirmation_message_value: "確定要刪除管理員 #{user.full_name} 嗎？",
          turbo_method: :delete
        },
        class: "text-red-600 hover:text-red-900" do %>
      刪除
    <% end %>
  </td>
</tr>
```

### 4. 建立 Stimulus 控制器

#### 4.1 確認對話框控制器

```javascript
// app/javascript/controllers/confirmation_controller.js
import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static values = { message: String }

    connect() {
        this.element.addEventListener('click', this.handleClick.bind(this))
    }

    handleClick(event) {
        const message = this.messageValue || '確定要執行此操作嗎？'

        if (!confirm(message)) {
            event.preventDefault()
            event.stopPropagation()
            return false
        }
    }
}
```

### 5. 路由設定

```ruby
# config/routes.rb (更新)
Rails.application.routes.draw do
  devise_for :users

  namespace :admin do
    root 'dashboard#index'

    resources :users do
      member do
        patch :toggle_status
      end
    end

    resources :restaurants
  end

  root 'admin/dashboard#index'
end
```

## 完成檢查

### 功能檢查

-   [ ] 管理員列表頁面可以正常顯示
-   [ ] 即時搜尋功能正常（輸入後無需重新載入頁面）
-   [ ] 新增管理員功能正常，會顯示產生的密碼
-   [ ] 編輯管理員功能正常
-   [ ] 狀態切換按鈕正常（即時更新，無需重新載入）
-   [ ] 刪除功能正常，有確認對話框
-   [ ] 分頁功能正常

### UI 檢查

-   [ ] Tailwind 樣式正確套用
-   [ ] 響應式設計在不同尺寸螢幕正常
-   [ ] 按鈕 hover 效果正常
-   [ ] 表格樣式美觀易讀

### 權限檢查

-   [ ] 只有 Super Admin 可以存取管理員管理功能
-   [ ] 一般 Admin 無法存取此頁面

## 下一步

完成後進行 Phase 3: 餐廳管理功能
