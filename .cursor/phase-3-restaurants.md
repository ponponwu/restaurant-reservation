# Phase 3: 餐廳管理功能實作

## 目標

完成餐廳的 CRUD 功能，包含即時搜尋、狀態切換等 Hotwire 互動功能。

## 前置條件

-   Phase 1 已完成（Rails 基礎設定）
-   Phase 2 已完成（管理員功能）
-   Restaurant 模型已建立

## 任務清單

### 1. 完善 Restaurant 模型

#### 1.2 更新 User 模型關聯

```ruby
# app/models/user.rb (新增)
belongs_to :restaurant, optional: true

# 新增 scope
scope :by_restaurant, ->(restaurant_id) {
  where(restaurant_id: restaurant_id) if restaurant_id.present?
}
```

### 2. 建立餐廳控制器

#### 2.1 Admin::RestaurantsController

```ruby
# app/controllers/admin/restaurants_controller.rb
class Admin::RestaurantsController < AdminController
  before_action :set_restaurant, only: [:show, :edit, :update, :destroy, :toggle_status]

  def index
    @q = Restaurant.active.ransack(params[:q])
    @restaurants = @q.result.includes(:users).page(params[:page]).per(10)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show
    @users = @restaurant.users.active.limit(5)
  end

  def new
    @restaurant = Restaurant.new
  end

  def create
    @restaurant = Restaurant.new(restaurant_params)

    if @restaurant.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.prepend('restaurants_list', partial: 'restaurant_row', locals: { restaurant: @restaurant }),
            turbo_stream.update('restaurant_form', partial: 'form', locals: { restaurant: Restaurant.new }),
            turbo_stream.update('flash_messages', partial: 'shared/flash', locals: { message: '餐廳建立成功', type: 'success' })
          ]
        end
        format.html { redirect_to admin_restaurants_path, notice: '餐廳建立成功' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('restaurant_form', partial: 'form', locals: { restaurant: @restaurant })
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    if @restaurant.update(restaurant_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("restaurant_#{@restaurant.id}", partial: 'restaurant_row', locals: { restaurant: @restaurant }),
            turbo_stream.update('flash_messages', partial: 'shared/flash', locals: { message: '餐廳資料已更新', type: 'success' })
          ]
        end
        format.html { redirect_to admin_restaurants_path, notice: '餐廳資料已更新' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('restaurant_form', partial: 'form', locals: { restaurant: @restaurant })
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @restaurant.soft_delete!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("restaurant_#{@restaurant.id}"),
          turbo_stream.update('flash_messages', partial: 'shared/flash', locals: { message: '餐廳已刪除', type: 'success' })
        ]
      end
      format.html { redirect_to admin_restaurants_path, notice: '餐廳已刪除' }
    end
  end

  def toggle_status
    @restaurant.update!(active: !@restaurant.active?)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("restaurant_#{@restaurant.id}", partial: 'restaurant_row', locals: { restaurant: @restaurant })
      end
    end
  end

  private

  def set_restaurant
    @restaurant = Restaurant.find(params[:id])
  end

  def restaurant_params
    params.require(:restaurant).permit(:name, :phone, :address)
  end
end
```

### 3. 建立餐廳視圖檔案

#### 3.1 餐廳列表頁面

```erb
<!-- app/views/admin/restaurants/index.html.erb -->
<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <div class="sm:flex sm:items-center">
    <div class="sm:flex-auto">
      <h1 class="text-2xl font-semibold text-gray-900">餐廳管理</h1>
      <p class="mt-2 text-sm text-gray-700">管理系統內所有餐廳資料</p>
    </div>
    <div class="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
      <%= link_to new_admin_restaurant_path,
          class: "inline-flex items-center justify-center rounded-md border border-transparent bg-blue-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 sm:w-auto" do %>
        新增餐廳
      <% end %>
    </div>
  </div>

  <!-- 搜尋區域 -->
  <%= turbo_frame_tag "search_form", class: "mt-6" do %>
    <%= search_form_for @q, url: admin_restaurants_path, local: false,
        data: { turbo_frame: "restaurants_table", turbo_action: "advance" },
        class: "max-w-md" do |f| %>
      <div class="flex rounded-md shadow-sm">
        <%= f.search_field :name_cont,
            placeholder: "搜尋餐廳名稱...",
            class: "flex-1 min-w-0 block w-full px-3 py-2 rounded-none rounded-l-md border-gray-300 focus:ring-blue-500 focus:border-blue-500 sm:text-sm" %>
        <%= f.submit "搜尋",
            class: "inline-flex items-center px-3 py-2 border border-l-0 border-gray-300 rounded-r-md bg-gray-50 text-gray-500 text-sm hover:bg-gray-100" %>
      </div>
    <% end %>
  <% end %>

  <!-- 表格區域 -->
  <%= turbo_frame_tag "restaurants_table", class: "mt-8 flex flex-col" do %>
    <div class="-my-2 -mx-4 overflow-x-auto sm:-mx-6 lg:-mx-8">
      <div class="inline-block min-w-full py-2 align-middle md:px-6 lg:px-8">
        <div class="overflow-hidden shadow ring-1 ring-black ring-opacity-5 md:rounded-lg">
          <table class="min-w-full divide-y divide-gray-300">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">餐廳名稱</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">電話</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">地址</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">管理員數</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">狀態</th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wide">操作</th>
              </tr>
            </thead>
            <tbody id="restaurants_list" class="bg-white divide-y divide-gray-200">
              <% @restaurants.each do |restaurant| %>
                <%= render 'restaurant_row', restaurant: restaurant %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- 分頁 -->
    <div class="mt-4">
      <%= paginate @restaurants, theme: 'twitter_bootstrap_4' %>
    </div>
  <% end %>
</div>

<!-- Flash 訊息區域 -->
<div id="flash_messages" class="fixed top-4 right-4 z-50">
  <%= render 'shared/flash' if notice || alert %>
</div>
```

#### 3.2 餐廳列表項目

```erb
<!-- app/views/admin/restaurants/_restaurant_row.html.erb -->
<tr id="restaurant_<%= restaurant.id %>" class="hover:bg-gray-50">
  <td class="whitespace-nowrap px-6 py-4 text-sm">
    <div class="flex items-center">
      <div>
        <div class="text-sm font-medium text-gray-900"><%= restaurant.name %></div>
      </div>
    </div>
  </td>
  <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">
    <%= restaurant.phone %>
  </td>
  <td class="px-6 py-4 text-sm text-gray-500">
    <div class="max-w-xs truncate">
      <%= restaurant.address %>
    </div>
  </td>
  <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">
    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
      <%= restaurant.users_count %> 人
    </span>
  </td>
  <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">
    <%= button_to toggle_status_admin_restaurant_path(restaurant),
        method: :patch, remote: true,
        class: "inline-flex px-2 py-1 text-xs font-semibold rounded-full border-0
                #{restaurant.active? ? 'bg-green-100 text-green-800 hover:bg-green-200' : 'bg-red-100 text-red-800 hover:bg-red-200'}" do %>
      <%= restaurant.active? ? '營業中' : '已停業' %>
    <% end %>
  </td>
  <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-6">
    <%= link_to admin_restaurant_path(restaurant), class: "text-blue-600 hover:text-blue-900 mr-4" do %>
      檢視
    <% end %>
    <%= link_to edit_admin_restaurant_path(restaurant), class: "text-blue-600 hover:text-blue-900 mr-4" do %>
      編輯
    <% end %>
    <%= button_to admin_restaurant_path(restaurant), method: :delete,
        data: {
          controller: "confirmation",
          confirmation_message_value: "確定要刪除餐廳 #{restaurant.name} 嗎？",
          turbo_method: :delete
        },
        class: "text-red-600 hover:text-red-900" do %>
      刪除
    <% end %>
  </td>
</tr>
```

#### 3.3 新增/編輯餐廳表單

```erb
<!-- app/views/admin/restaurants/new.html.erb -->
<div class="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <div class="md:grid md:grid-cols-3 md:gap-6">
    <div class="md:col-span-1">
      <div class="px-4 sm:px-0">
        <h3 class="text-lg font-medium leading-6 text-gray-900">新增餐廳</h3>
        <p class="mt-1 text-sm text-gray-600">請填寫餐廳的基本資料</p>
      </div>
    </div>
    <div class="mt-5 md:col-span-2 md:mt-0">
      <%= turbo_frame_tag "restaurant_form" do %>
        <%= render 'form', restaurant: @restaurant %>
      <% end %>
    </div>
  </div>
</div>
```

```erb
<!-- app/views/admin/restaurants/edit.html.erb -->
<div class="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <div class="md:grid md:grid-cols-3 md:gap-6">
    <div class="md:col-span-1">
      <div class="px-4 sm:px-0">
        <h3 class="text-lg font-medium leading-6 text-gray-900">編輯餐廳</h3>
        <p class="mt-1 text-sm text-gray-600">修改餐廳的基本資料</p>
      </div>
    </div>
    <div class="mt-5 md:col-span-2 md:mt-0">
      <%= turbo_frame_tag "restaurant_form" do %>
        <%= render 'form', restaurant: @restaurant %>
      <% end %>
    </div>
  </div>
</div>
```

```erb
<!-- app/views/admin/restaurants/_form.html.erb -->
<div class="shadow sm:overflow-hidden sm:rounded-md">
  <%= form_with model: [:admin, restaurant],
      data: { turbo_frame: "restaurant_form" },
      class: "space-y-6 bg-white py-6 px-4 sm:p-6" do |f| %>

    <!-- 錯誤訊息 -->
    <% if restaurant.errors.any? %>
      <div class="rounded-md bg-red-50 p-4">
        <div class="flex">
          <div class="flex-shrink-0">
            <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
            </svg>
          </div>
          <div class="ml-3">
            <h3 class="text-sm font-medium text-red-800">表單驗證錯誤</h3>
            <div class="mt-2 text-sm text-red-700">
              <ul class="list-disc space-y-1 pl-5">
                <% restaurant.errors.full_messages.each do |message| %>
                  <li><%= message %></li>
                <% end %>
              </ul>
            </div>
          </div>
        </div>
      </div>
    <% end %>

    <div class="grid grid-cols-6 gap-6">
      <!-- 餐廳名稱 -->
      <div class="col-span-6 sm:col-span-4">
        <%= f.label :name, "餐廳名稱", class: "block text-sm font-medium text-gray-700" %>
        <%= f.text_field :name,
            class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm #{'border-red-300' if restaurant.errors[:name].any?}" %>
      </div>

      <!-- 電話號碼 -->
      <div class="col-span-6 sm:col-span-3">
        <%= f.label :phone, "電話號碼", class: "block text-sm font-medium text-gray-700" %>
        <%= f.telephone_field :phone,
            class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm #{'border-red-300' if restaurant.errors[:phone].any?}" %>
      </div>

      <!-- 地址 -->
      <div class="col-span-6">
        <%= f.label :address, "地址", class: "block text-sm font-medium text-gray-700" %>
        <%= f.text_area :address, rows: 3,
            class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm #{'border-red-300' if restaurant.errors[:address].any?}" %>
      </div>
    </div>

    <!-- 按鈕區域 -->
    <div class="flex justify-end space-x-3">
      <%= link_to admin_restaurants_path,
          class: "rounded-md border border-gray-300 bg-white py-2 px-4 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2" do %>
        取消
      <% end %>
      <%= f.submit (restaurant.persisted? ? "更新餐廳" : "建立餐廳"),
          class: "inline-flex justify-center rounded-md border border-transparent bg-blue-600 py-2 px-4 text-sm font-medium text-white shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2" %>
    </div>
  <% end %>
</div>
```

#### 3.4 餐廳詳細頁面

```erb
<!-- app/views/admin/restaurants/show.html.erb -->
<div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <!-- 標題區域 -->
  <div class="mb-8">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-bold text-gray-900"><%= @restaurant.name %></h1>
        <p class="mt-1 text-sm text-gray-500">餐廳詳細資訊</p>
      </div>
      <div class="flex space-x-3">
        <%= link_to edit_admin_restaurant_path(@restaurant),
            class: "inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500" do %>
          編輯餐廳
        <% end %>
        <%= link_to admin_restaurants_path,
            class: "inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500" do %>
          返回列表
        <% end %>
      </div>
    </div>
  </div>

  <!-- 餐廳基本資訊 -->
  <div class="bg-white shadow overflow-hidden sm:rounded-lg mb-8">
    <div class="px-4 py-5 sm:px-6">
      <h3 class="text-lg leading-6 font-medium text-gray-900">基本資訊</h3>
      <p class="mt-1 max-w-2xl text-sm text-gray-500">餐廳的基本資料和聯絡方式</p>
    </div>
    <div class="border-t border-gray-200">
      <dl>
        <div class="bg-gray-50 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
          <dt class="text-sm font-medium text-gray-500">餐廳名稱</dt>
          <dd class="mt-1 text-sm text-gray-900 sm:col-span-2 sm:mt-0"><%= @restaurant.name %></dd>
        </div>
        <div class="bg-white px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
          <dt class="text-sm font-medium text-gray-500">電話號碼</dt>
          <dd class="mt-1 text-sm text-gray-900 sm:col-span-2 sm:mt-0"><%= @restaurant.phone %></dd>
        </div>
        <div class="bg-gray-50 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
          <dt class="text-sm font-medium text-gray-500">地址</dt>
          <dd class="mt-1 text-sm text-gray-900 sm:col-span-2 sm:mt-0"><%= @restaurant.address %></dd>
        </div>
        <div class="bg-white px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
          <dt class="text-sm font-medium text-gray-500">狀態</dt>
          <dd class="mt-1 text-sm text-gray-900 sm:col-span-2 sm:mt-0">
            <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full
                         <%= @restaurant.active? ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800' %>">
              <%= @restaurant.active? ? '營業中' : '已停業' %>
            </span>
          </dd>
        </div>
      </dl>
    </div>
  </div>

  <!-- 管理員列表 -->
  <div class="bg-white shadow overflow-hidden sm:rounded-lg">
    <div class="px-4 py-5 sm:px-6">
      <h3 class="text-lg leading-6 font-medium text-gray-900">管理員</h3>
      <p class="mt-1 max-w-2xl text-sm text-gray-500">此餐廳的管理員列表</p>
    </div>
    <div class="border-t border-gray-200">
      <% if @users.any? %>
        <ul class="divide-y divide-gray-200">
          <% @users.each do |user| %>
            <li class="px-4 py-4 sm:px-6">
              <div class="flex items-center justify-between">
                <div class="flex items-center">
                  <div class="flex-shrink-0 h-10 w-10">
                    <div class="h-10 w-10 rounded-full bg-blue-100 flex items-center justify-center">
                      <span class="text-sm font-medium text-blue-600">
                        <%= user.first_name[0].upcase %>
                      </span>
                    </div>
                  </div>
                  <div class="ml-4">
                    <div class="text-sm font-medium text-gray-900"><%= user.full_name %></div>
                    <div class="text-sm text-gray-500"><%= user.email %></div>
                  </div>
                </div>
                <div class="flex items-center">
                  <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full
                               <%= user.super_admin? ? 'bg-purple-100 text-purple-800' : 'bg-blue-100 text-blue-800' %>">
                    <%= user.super_admin? ? 'Super Admin' : '管理員' %>
                  </span>
                </div>
              </div>
            </li>
          <% end %>
        </ul>
      <% else %>
        <div class="text-center py-12">
          <p class="text-sm text-gray-500">此餐廳尚未指派管理員</p>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

### 4. 更新路由設定

```ruby
# config/routes.rb (更新餐廳路由)
Rails.application.routes.draw do
  devise_for :users

  namespace :admin do
    root 'dashboard#index'

    resources :users do
      member do
        patch :toggle_status
      end
    end

    resources :restaurants do
      member do
        patch :toggle_status
      end
    end
  end

  root 'admin/dashboard#index'
end
```

### 5. 新增 Ransack 設定

```ruby
# config/initializers/ransack.rb (建立此檔案)
Ransack.configure do |config|
  # 設定允許的搜尋屬性，增強安全性
  config.sanitize_custom_scope_args = true
end
```

### 6. 新增 Kaminari 分頁設定

```ruby
# config/initializers/kaminari_config.rb (建立此檔案)
Kaminari.configure do |config|
  config.default_per_page = 10
  config.max_per_page = 50
  config.window = 2
  config.outer_window = 1
  config.left = 2
  config.right = 2
end
```

## 完成檢查

### 功能檢查

-   [ ] 餐廳列表頁面可以正常顯示
-   [ ] 即時搜尋功能正常（按餐廳名稱搜尋）
-   [ ] 新增餐廳功能正常
-   [ ] 編輯餐廳功能正常
-   [ ] 餐廳詳細頁面正常，顯示基本資訊和管理員列表
-   [ ] 狀態切換按鈕正常（營業中/已停業）
-   [ ] 刪除功能正常，有確認對話框
-   [ ] 分頁功能正常

### UI 檢查

-   [ ] Tailwind 樣式正確套用
-   [ ] 表單樣式美觀，驗證錯誤顯示正確
-   [ ] 響應式設計在不同尺寸螢幕正常
-   [ ] 按鈕 hover 效果正常
-   [ ] 表格樣式美觀易讀

### 資料檢查

-   [ ] 餐廳與管理員的關聯正常
-   [ ] 軟刪除功能正常
-   [ ] 搜尋功能回傳正確結果

### 權限檢查

-   [ ] 只有 Super Admin 可以存取餐廳管理功能
-   [ ] 一般 Admin 無法存取此頁面

## 下一步

完成後進行 Phase 4: Dashboard 儀表板功能
