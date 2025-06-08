# Phase 4: Dashboard 儀表板實作

## 目標

建立簡潔美觀的 Dashboard 儀表板，顯示系統基本統計資訊和最近活動。

## 前置條件

-   Phase 1-3 已完成
-   User 與 Restaurant 模型功能正常

## 任務清單

### 1. 建立 Dashboard 控制器

#### 1.1 Admin::DashboardController

```ruby
# app/controllers/admin/dashboard_controller.rb
class Admin::DashboardController < AdminController
  def index
    @stats = dashboard_stats
    @recent_activities = recent_activities
    @system_status = system_status
  end

  private

  def dashboard_stats
    {
      total_users: User.active.count,
      total_restaurants: Restaurant.active.count,
      super_admins: User.active.super_admin.count,
      regular_admins: User.active.admin.count,
      active_restaurants: Restaurant.active.where(active: true).count,
      inactive_restaurants: Restaurant.active.where(active: false).count
    }
  end

  def recent_activities
    # 簡單的活動記錄 - 最近建立的使用者和餐廳
    activities = []

    # 最近建立的使用者
    User.active.order(created_at: :desc).limit(3).each do |user|
      activities << {
        type: 'user_created',
        description: "新管理員 #{user.full_name} 已建立",
        timestamp: user.created_at,
        icon: 'user',
        color: 'blue'
      }
    end

    # 最近建立的餐廳
    Restaurant.active.order(created_at: :desc).limit(3).each do |restaurant|
      activities << {
        type: 'restaurant_created',
        description: "新餐廳 #{restaurant.name} 已建立",
        timestamp: restaurant.created_at,
        icon: 'building',
        color: 'green'
      }
    end

    # 按時間排序並取前5筆
    activities.sort_by { |a| a[:timestamp] }.reverse.first(5)
  end

  def system_status
    {
      database: database_status,
      users_health: users_health_status,
      restaurants_health: restaurants_health_status
    }
  end

  def database_status
    begin
      ActiveRecord::Base.connection.execute('SELECT 1')
      'healthy'
    rescue => e
      'error'
    end
  end

  def users_health_status
    inactive_users = User.where(active: false).count
    total_users = User.count

    if total_users == 0
      'warning'
    elsif inactive_users.to_f / total_users > 0.3
      'warning'
    else
      'healthy'
    end
  end

  def restaurants_health_status
    inactive_restaurants = Restaurant.where(active: false).count
    total_restaurants = Restaurant.count

    if total_restaurants == 0
      'warning'
    elsif inactive_restaurants.to_f / total_restaurants > 0.5
      'warning'
    else
      'healthy'
    end
  end
end
```

### 2. 建立 Dashboard 視圖

#### 2.1 Dashboard 主頁面

```erb
<!-- app/views/admin/dashboard/index.html.erb -->
<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <!-- 頁面標題 -->
  <div class="md:flex md:items-center md:justify-between mb-8">
    <div class="flex-1 min-w-0">
      <h2 class="text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate">
        儀表板
      </h2>
      <p class="mt-1 text-sm text-gray-500">
        歡迎回來，<%= current_user.full_name %>
      </p>
    </div>
    <div class="mt-4 flex md:mt-0 md:ml-4">
      <span class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500">
        <%= Date.current.strftime("%Y年%m月%d日") %>
      </span>
    </div>
  </div>

  <!-- 統計卡片區域 -->
  <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4 mb-8">
    <!-- 總管理員數 -->
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <div class="w-8 h-8 bg-blue-500 rounded-md flex items-center justify-center">
              <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z" />
              </svg>
            </div>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">總管理員數</dt>
              <dd class="text-lg font-medium text-gray-900"><%= @stats[:total_users] %></dd>
            </dl>
          </div>
        </div>
      </div>
      <div class="bg-gray-50 px-5 py-3">
        <div class="text-sm">
          <span class="text-blue-600 font-medium"><%= @stats[:super_admins] %></span>
          <span class="text-gray-500"> Super Admin・</span>
          <span class="text-blue-600 font-medium"><%= @stats[:regular_admins] %></span>
          <span class="text-gray-500"> 一般管理員</span>
        </div>
      </div>
    </div>

    <!-- 總餐廳數 -->
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <div class="w-8 h-8 bg-green-500 rounded-md flex items-center justify-center">
              <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
              </svg>
            </div>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">總餐廳數</dt>
              <dd class="text-lg font-medium text-gray-900"><%= @stats[:total_restaurants] %></dd>
            </dl>
          </div>
        </div>
      </div>
      <div class="bg-gray-50 px-5 py-3">
        <div class="text-sm">
          <span class="text-green-600 font-medium"><%= @stats[:active_restaurants] %></span>
          <span class="text-gray-500"> 營業中・</span>
          <span class="text-red-600 font-medium"><%= @stats[:inactive_restaurants] %></span>
          <span class="text-gray-500"> 已停業</span>
        </div>
      </div>
    </div>

    <!-- 系統狀態 -->
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <div class="w-8 h-8 <%= system_status_color(@system_status) %> rounded-md flex items-center justify-center">
              <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">系統狀態</dt>
              <dd class="text-lg font-medium text-gray-900"><%= system_status_text(@system_status) %></dd>
            </dl>
          </div>
        </div>
      </div>
      <div class="bg-gray-50 px-5 py-3">
        <div class="text-sm text-gray-500">
          資料庫: <%= @system_status[:database] == 'healthy' ? '正常' : '異常' %>
        </div>
      </div>
    </div>

    <!-- 快速操作 -->
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <div class="w-8 h-8 bg-purple-500 rounded-md flex items-center justify-center">
              <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">快速操作</dt>
              <dd class="text-lg font-medium text-gray-900">管理功能</dd>
            </dl>
          </div>
        </div>
      </div>
      <div class="bg-gray-50 px-5 py-3">
        <div class="flex space-x-2">
          <%= link_to new_admin_user_path, class: "text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded hover:bg-blue-200" do %>
            新增管理員
          <% end %>
          <%= link_to new_admin_restaurant_path, class: "text-xs bg-green-100 text-green-800 px-2 py-1 rounded hover:bg-green-200" do %>
            新增餐廳
          <% end %>
        </div>
      </div>
    </div>
  </div>

  <!-- 主要內容區域 -->
  <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
    <!-- 最近活動 -->
    <div class="bg-white shadow rounded-lg">
      <div class="px-4 py-5 sm:p-6">
        <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">最近活動</h3>
        <div class="flow-root">
          <% if @recent_activities.any? %>
            <ul class="-mb-8">
              <% @recent_activities.each_with_index do |activity, index| %>
                <li>
                  <div class="relative pb-8">
                    <% unless index == @recent_activities.length - 1 %>
                      <span class="absolute top-4 left-4 -ml-px h-full w-0.5 bg-gray-200" aria-hidden="true"></span>
                    <% end %>
                    <div class="relative flex space-x-3">
                      <div>
                        <span class="h-8 w-8
```
