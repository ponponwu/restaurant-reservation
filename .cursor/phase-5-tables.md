# 桌位管理功能規格書

## 📋 功能概述

建立餐廳桌位與桌位群組的管理系統，支援拖曳排序來設定訂位優先順序，讓餐廳管理員能夠靈活配置桌位佈局和分配策略。

## 🎯 核心需求

### 業務邏輯

1. **桌位群組** - 將桌位按區域或類型分組（如：主用餐區、VIP 包廂、吧台區）
2. **優先順序** - 每個群組和桌位都有排序權重，影響自動分配桌位的順序
3. **拖曳排序** - 透過拖曳操作調整群組和桌位的順序
4. **即時更新** - 拖曳完成後立即儲存新的排序

### 使用場景

-   餐廳初次設定桌位配置
-   調整不同區域的優先順序（如：優先分配景觀位、避開吵雜區域）
-   季節性調整（如：夏天優先戶外區、冬天優先室內區）
-   特殊活動時的桌位重新排序

## 🗃️ 資料表設計

### TableGroup（桌位群組）

```ruby
# == Schema Information
#
# Table name: table_groups
#
#  id            :bigint           not null, primary key
#  restaurant_id :bigint           not null
#  name          :string           not null              # 群組名稱
#  description   :text                                   # 群組描述
#  sort_order    :integer          default(0)           # 排序權重（數字越小越優先）
#  active        :boolean          default(true)        # 是否啟用
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_table_groups_on_restaurant_id                    (restaurant_id)
#  index_table_groups_on_restaurant_id_and_sort_order     (restaurant_id, sort_order)
#
```

### Table（桌位）

```ruby
# == Schema Information
#
# Table name: tables
#
#  id              :bigint           not null, primary key
#  restaurant_id   :bigint           not null
#  table_group_id  :bigint           not null
#  table_number    :string           not null             # 桌號
#  capacity        :integer          not null             # 標準容量
#  min_capacity    :integer          default(1)          # 最小容量
#  max_capacity    :integer                              # 最大容量（可併桌）
#  table_type      :string           default('regular')   # 桌位類型
#  sort_order      :integer          default(0)          # 群組內排序權重
#  status          :string           default('available') # 桌位狀態
#  metadata        :json                                 # 額外資訊（位置、特色等）
#  active          :boolean          default(true)        # 是否啟用
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_tables_on_restaurant_id                          (restaurant_id)
#  index_tables_on_table_group_id                         (table_group_id)
#  index_tables_on_restaurant_id_and_table_number         (restaurant_id, table_number) UNIQUE
#  index_tables_on_table_group_id_and_sort_order          (table_group_id, sort_order)
#
```

## 🏗️ 模型設計

### TableGroup 模型

```ruby
class TableGroup < ApplicationRecord
  belongs_to :restaurant
  has_many :tables, -> { order(:sort_order) }, dependent: :destroy

  validates :name, presence: true, length: { maximum: 50 }
  validates :sort_order, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:sort_order, :id) }

  # 重新排序群組
  def self.reorder!(ordered_ids)
    transaction do
      ordered_ids.each_with_index do |id, index|
        where(id: id).update_all(sort_order: index + 1)
      end
    end
  end

  # 下一個排序號碼
  def self.next_sort_order(restaurant)
    restaurant.table_groups.maximum(:sort_order).to_i + 1
  end

  def tables_count
    tables.active.count
  end

  def available_tables_count
    tables.active.where(status: 'available').count
  end
end
```

### Table 模型

```ruby
class Table < ApplicationRecord
  belongs_to :restaurant
  belongs_to :table_group
  has_many :reservations, dependent: :restrict_with_error

  validates :table_number, presence: true, length: { maximum: 10 }
  validates :table_number, uniqueness: { scope: :restaurant_id }
  validates :capacity, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 20 }
  validates :min_capacity, numericality: { greater_than: 0 }
  validates :max_capacity, numericality: { greater_than_or_equal_to: :capacity }, allow_blank: true
  validates :sort_order, presence: true, numericality: { greater_than_or_equal_to: 0 }

  enum table_type: {
    regular: 'regular',           # 一般桌位
    round: 'round',              # 圓桌
    square: 'square',            # 方桌
    booth: 'booth',              # 卡座
    bar: 'bar',                  # 吧台座位
    private_room: 'private_room', # 包廂
    outdoor: 'outdoor',          # 戶外座位
    counter: 'counter'           # 櫃台座位
  }

  enum status: {
    available: 'available',       # 可用
    occupied: 'occupied',         # 使用中
    reserved: 'reserved',         # 已預訂
    maintenance: 'maintenance',   # 維修中
    cleaning: 'cleaning'          # 清潔中
  }

  scope :active, -> { where(active: true) }
  scope :available_for_booking, -> { active.where(status: %w[available]) }
  scope :ordered, -> { order(:sort_order, :id) }

  # 重新排序桌位（群組內）
  def self.reorder_in_group!(table_group, ordered_ids)
    transaction do
      ordered_ids.each_with_index do |id, index|
        where(id: id, table_group: table_group).update_all(sort_order: index + 1)
      end
    end
  end

  # 下一個排序號碼（群組內）
  def self.next_sort_order_in_group(table_group)
    table_group.tables.maximum(:sort_order).to_i + 1
  end

  # 是否適合指定人數
  def suitable_for?(party_size)
    return false unless active? && available_for_booking?
    return false if party_size < min_capacity
    return false if max_capacity.present? && party_size > max_capacity
    true
  end

  # 容量描述
  def capacity_description
    if max_capacity.present? && max_capacity > capacity
      "#{min_capacity}-#{max_capacity}人"
    else
      "#{capacity}人"
    end
  end
end
```

## 🎨 前端介面設計

### 桌位群組管理頁面

```
桌位群組管理
├── 新增群組按鈕
├── 群組列表（可拖曳排序）
│   ├── 群組卡片 1
│   │   ├── 群組資訊（名稱、描述、桌位數量）
│   │   ├── 拖曳手柄
│   │   ├── 編輯/刪除按鈕
│   │   └── 桌位列表（可拖曳排序）
│   │       ├── 桌位項目 1
│   │       ├── 桌位項目 2
│   │       └── ...
│   ├── 群組卡片 2
│   └── ...
└── 儲存順序按鈕
```

### 拖曳互動設計

-   **群組拖曳**：可以調整群組之間的順序
-   **桌位拖曳**：可以在群組內調整桌位順序，也可以拖曳到其他群組
-   **視覺回饋**：拖曳時顯示拖曳預覽和放置區域
-   **即時儲存**：拖曳完成後自動儲存新順序

## 🔧 技術實作

### 控制器設計

#### Admin::TableGroupsController

```ruby
class Admin::TableGroupsController < AdminController
  before_action :set_restaurant
  before_action :set_table_group, only: [:show, :edit, :update, :destroy, :reorder_tables]

  def index
    @table_groups = @restaurant.table_groups.active.ordered.includes(:tables)
  end

  def show
    @tables = @table_group.tables.active.ordered
  end

  def new
    @table_group = @restaurant.table_groups.build(
      sort_order: TableGroup.next_sort_order(@restaurant)
    )
  end

  def create
    @table_group = @restaurant.table_groups.build(table_group_params)

    if @table_group.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append('table_groups_list', partial: 'table_group_card', locals: { table_group: @table_group }),
            turbo_stream.update('flash_messages', partial: 'shared/flash', locals: { message: '桌位群組建立成功', type: 'success' })
          ]
        end
        format.html { redirect_to admin_restaurant_table_groups_path(@restaurant), notice: '桌位群組建立成功' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update('table_group_form', partial: 'form', locals: { table_group: @table_group })
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def reorder
    ordered_ids = params[:ordered_ids]

    if TableGroup.reorder!(ordered_ids)
      render json: { success: true, message: '群組順序已更新' }
    else
      render json: { success: false, message: '更新失敗' }, status: :unprocessable_entity
    end
  end

  def reorder_tables
    ordered_ids = params[:ordered_ids]

    if Table.reorder_in_group!(@table_group, ordered_ids)
      render json: { success: true, message: '桌位順序已更新' }
    else
      render json: { success: false, message: '更新失敗' }, status: :unprocessable_entity
    end
  end

  private

  def set_restaurant
    @restaurant = current_user.restaurant || Restaurant.find(params[:restaurant_id])
  end

  def set_table_group
    @table_group = @restaurant.table_groups.find(params[:id])
  end

  def table_group_params
    params.require(:table_group).permit(:name, :description, :sort_order)
  end
end
```

### Stimulus 拖曳控制器

#### sortable_controller.js

```javascript
import { Controller } from '@hotwired/stimulus'
import Sortable from 'sortablejs'

export default class extends Controller {
    static values = {
        url: String,
        group: String,
    }
    static targets = ['container']

    connect() {
        this.sortable = Sortable.create(this.containerTarget, {
            group: this.groupValue || 'default',
            animation: 150,
            ghostClass: 'sortable-ghost',
            dragClass: 'sortable-drag',
            onEnd: this.handleSortEnd.bind(this),
        })
    }

    disconnect() {
        if (this.sortable) {
            this.sortable.destroy()
        }
    }

    async handleSortEnd(event) {
        const orderedIds = Array.from(this.containerTarget.children).map((element) => element.dataset.id)

        try {
            const response = await fetch(this.urlValue, {
                method: 'PATCH',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': this.getCSRFToken(),
                },
                body: JSON.stringify({ ordered_ids: orderedIds }),
            })

            const result = await response.json()

            if (result.success) {
                this.showFlash(result.message, 'success')
            } else {
                this.showFlash(result.message, 'error')
                // 恢復原始順序
                this.sortable.sort(this.originalOrder)
            }
        } catch (error) {
            console.error('排序更新失敗:', error)
            this.showFlash('網路錯誤，請稍後再試', 'error')
            this.sortable.sort(this.originalOrder)
        }
    }

    getCSRFToken() {
        return document.querySelector('[name="csrf-token"]').content
    }

    showFlash(message, type) {
        // 實作 flash 訊息顯示
        const flashContainer = document.getElementById('flash_messages')
        if (flashContainer) {
            flashContainer.innerHTML = `
        <div class="rounded-md p-4 mb-4 ${this.getFlashClass(type)}">
          <p class="text-sm font-medium">${message}</p>
        </div>
      `

            setTimeout(() => {
                flashContainer.innerHTML = ''
            }, 3000)
        }
    }

    getFlashClass(type) {
        return type === 'success'
            ? 'bg-green-50 text-green-800 border border-green-200'
            : 'bg-red-50 text-red-800 border border-red-200'
    }
}
```

### 視圖設計

#### 桌位群組列表

```erb
<!-- app/views/admin/table_groups/index.html.erb -->
<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <div class="sm:flex sm:items-center mb-8">
    <div class="sm:flex-auto">
      <h1 class="text-2xl font-semibold text-gray-900">桌位管理</h1>
      <p class="mt-2 text-sm text-gray-700">管理餐廳的桌位群組和桌位配置，拖曳調整優先順序</p>
    </div>
    <div class="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
      <%= link_to new_admin_restaurant_table_group_path(@restaurant),
          class: "inline-flex items-center justify-center rounded-md border border-transparent bg-blue-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2" do %>
        新增桌位群組
      <% end %>
    </div>
  </div>

  <!-- 拖曳排序說明 -->
  <div class="bg-blue-50 border border-blue-200 rounded-md p-4 mb-6">
    <div class="flex">
      <div class="flex-shrink-0">
        <svg class="h-5 w-5 text-blue-400" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
        </svg>
      </div>
      <div class="ml-3">
        <h3 class="text-sm font-medium text-blue-800">拖曳排序說明</h3>
        <div class="mt-2 text-sm text-blue-700">
          <p>• 拖曳群組卡片可調整群組優先順序</p>
          <p>• 拖曳桌位項目可調整群組內桌位順序</p>
          <p>• 順序越前面，自動分配桌位時優先級越高</p>
        </div>
      </div>
    </div>
  </div>

  <!-- 桌位群組列表 -->
  <div id="table_groups_list"
       data-controller="sortable"
       data-sortable-url-value="<%= reorder_admin_restaurant_table_groups_path(@restaurant) %>"
       data-sortable-group-value="table_groups">
    <div data-sortable-target="container">
      <% @table_groups.each do |table_group| %>
        <%= render 'table_group_card', table_group: table_group %>
      <% end %>
    </div>
  </div>

  <% if @table_groups.empty? %>
    <div class="text-center py-12">
      <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
      </svg>
      <h3 class="mt-2 text-sm font-medium text-gray-900">尚未建立桌位群組</h3>
      <p class="mt-1 text-sm text-gray-500">開始建立第一個桌位群組來管理餐廳座位</p>
      <div class="mt-6">
        <%= link_to new_admin_restaurant_table_group_path(@restaurant),
            class: "inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500" do %>
          新增桌位群組
        <% end %>
      </div>
    </div>
  <% end %>
</div>

<!-- Flash 訊息區域 -->
<div id="flash_messages" class="fixed top-4 right-4 z-50">
  <%= render 'shared/flash' if notice || alert %>
</div>
```

#### 桌位群組卡片

```erb
<!-- app/views/admin/table_groups/_table_group_card.html.erb -->
<div class="bg-white shadow rounded-lg mb-6 sortable-item"
     data-id="<%= table_group.id %>">
  <!-- 群組標題區域 -->
  <div class="px-6 py-4 border-b border-gray-200">
    <div class="flex items-center justify-between">
      <div class="flex items-center">
        <!-- 拖曳手柄 -->
        <div class="mr-3 cursor-move text-gray-400 hover:text-gray-600">
          <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
            <path d="M10 6a2 2 0 110-4 2 2 0 010 4zM10 12a2 2 0 110-4 2 2 0 010 4zM10 18a2 2 0 110-4 2 2 0 010 4z" />
          </svg>
        </div>
        <div>
          <h3 class="text-lg font-medium text-gray-900"><%= table_group.name %></h3>
          <p class="text-sm text-gray-500"><%= table_group.description %></p>
        </div>
      </div>
      <div class="flex items-center space-x-2">
        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
          <%= table_group.tables_count %> 桌
        </span>
        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
          <%= table_group.available_tables_count %> 可用
        </span>
        <%= link_to edit_admin_restaurant_table_group_path(@restaurant, table_group),
            class: "text-blue-600 hover:text-blue-900 text-sm font-medium" do %>
          編輯
        <% end %>
      </div>
    </div>
  </div>

  <!-- 桌位列表區域 -->
  <div class="px-6 py-4">
    <div id="tables_list_<%= table_group.id %>"
         data-controller="sortable"
         data-sortable-url-value="<%= reorder_tables_admin_restaurant_table_group_path(@restaurant, table_group) %>"
         data-sortable-group-value="tables_<%= table_group.id %>">
      <div data-sortable-target="container" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
        <% table_group.tables.active.ordered.each do |table| %>
          <%= render 'table_item', table: table %>
        <% end %>
      </div>
    </div>

    <!-- 新增桌位按鈕 -->
    <div class="mt-4 pt-4 border-t border-gray-200">
      <%= link_to new_admin_restaurant_table_group_table_path(@restaurant, table_group),
          class: "inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500" do %>
        <svg class="-ml-0.5 mr-2 h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M10 5a1 1 0 011 1v3h3a1 1 0 110 2h-3v3a1 1 0 11-2 0v-3H6a1 1 0 110-2h3V6a1 1 0 011-1z" clip-rule="evenodd" />
        </svg>
        新增桌位
      <% end %>
    </div>
  </div>
</div>
```

## 📱 CSS 樣式

### 拖曳樣式

```css
/* app/assets/stylesheets/sortable.css */
.sortable-ghost {
    opacity: 0.4;
    background: #f3f4f6;
}

.sortable-drag {
    transform: rotate(5deg);
    box-shadow: 0 10px 25px rgba(0, 0, 0, 0.2);
    z-index: 1000;
}

.sortable-item {
    transition: all 0.2s ease;
}

.sortable-item:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.drag-handle {
    cursor: grab;
}

.drag-handle:active {
    cursor: grabbing;
}
```

## 🔄 路由設定

```ruby
# config/routes.rb
namespace :admin do
  resources :restaurants do
    resources :table_groups do
      member do
        patch :reorder_tables
      end

      collection do
        patch :reorder
      end

      resources :tables
    end
  end
end
```

## ✅ 開發檢查清單

### 後端功能

-   [ ] TableGroup 和 Table 模型建立完成
-   [ ] 排序相關方法實作完成
-   [ ] 控制器 CRUD 功能正常
-   [ ] 拖曳排序 API 端點正常
-   [ ] 資料庫索引設定完成

### 前端功能

-   [ ] 拖曳排序互動正常
-   [ ] 視覺回饋（拖曳預覽、放置區域）正常
-   [ ] 排序完成後自動儲存
-   [ ] 錯誤處理（網路錯誤時恢復原順序）
-   [ ] Flash 訊息顯示正常

### UI/UX

-   [ ] 拖曳手柄明顯易識別
-   [ ] 響應式設計在不同裝置正常
-   [ ] 動畫效果流暢自然
-   [ ] 載入狀態和錯誤狀態處理完善

## 🎯 後續擴展建議

1. **跨群組拖曳** - 允許桌位在不同群組間移動
2. **批量操作** - 多選桌位進行批量狀態變更
3. **視覺化座位圖** - 2D 平面圖拖拉放置
4. **自動排序建議** - 根據使用頻率自動建議最佳排序
5. **排序歷史記錄** - 記錄排序變更歷史，支援復原

這個設計提供了完整的桌位管理功能，支援靈活的拖曳排序，讓餐廳能夠根據實際需求調整桌位分配策略。
