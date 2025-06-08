# 餐廳訂位系統 - 專案結構

## 專案目錄結構

```
restaurant-reservation/
├── README.md                    # 專案說明文件
├── Gemfile                      # Ruby 依賴管理
├── Gemfile.lock                 # 鎖定的依賴版本
├── package.json                 # Node.js 依賴管理
├── yarn.lock                    # 鎖定的 Node.js 依賴版本
├── Rakefile                     # Rake 任務定義
├── config.ru                    # Rack 配置檔案
├── Procfile.dev                 # 開發環境程序定義
├── Dockerfile                   # Docker 容器配置
├── .dockerignore               # Docker 忽略檔案
├── .ruby-version               # Ruby 版本指定
├── .node-version               # Node.js 版本指定
├── .cursorrules                # Cursor AI 開發規範
│
├── app/                        # 應用程式主要程式碼
│   ├── controllers/            # 控制器層
│   │   ├── application_controller.rb
│   │   ├── admin/              # 管理後台控制器
│   │   │   ├── base_controller.rb
│   │   │   ├── dashboard_controller.rb
│   │   │   ├── reservations_controller.rb
│   │   │   ├── tables_controller.rb
│   │   │   └── users_controller.rb
│   │   └── api/                # API 控制器
│   │       └── v1/
│   │
│   ├── models/                 # 模型層
│   │   ├── application_record.rb
│   │   ├── user.rb             # 用戶模型
│   │   ├── restaurant.rb       # 餐廳模型
│   │   ├── table_group.rb      # 桌位群組模型
│   │   ├── table.rb            # 桌位模型
│   │   ├── business_period.rb  # 營業時段模型
│   │   ├── reservation.rb      # 訂位模型
│   │   └── concerns/           # 共用模組
│   │
│   ├── views/                  # 視圖層
│   │   ├── layouts/            # 版面配置
│   │   ├── admin/              # 管理後台視圖
│   │   ├── reservations/       # 訂位相關視圖
│   │   └── shared/             # 共用視圖組件
│   │
│   ├── services/               # 服務層
│   │   ├── reservation_service.rb
│   │   ├── table_service.rb
│   │   └── notification_service.rb
│   │
│   ├── jobs/                   # 背景任務
│   │   ├── application_job.rb
│   │   └── notification_job.rb
│   │
│   ├── mailers/                # 郵件發送器
│   │   ├── application_mailer.rb
│   │   └── reservation_mailer.rb
│   │
│   ├── helpers/                # 視圖輔助方法
│   │   └── application_helper.rb
│   │
│   └── assets/                 # 前端資源
│       ├── stylesheets/        # CSS 樣式
│       ├── javascripts/        # JavaScript 檔案
│       └── images/             # 圖片資源
│
├── config/                     # 配置檔案
│   ├── application.rb          # 應用程式配置
│   ├── routes.rb               # 路由定義
│   ├── database.yml            # 資料庫配置
│   ├── environments/           # 環境特定配置
│   │   ├── development.rb      # 開發環境
│   │   ├── test.rb             # 測試環境
│   │   └── production.rb       # 生產環境
│   ├── initializers/           # 初始化設定
│   └── locales/                # 國際化檔案
│
├── db/                         # 資料庫相關
│   ├── migrate/                # 資料庫遷移檔案
│   │   ├── 20250529110601_devise_create_users.rb
│   │   ├── 20250529110612_create_restaurants.rb
│   │   ├── 20250529110622_create_table_groups.rb
│   │   ├── 20250529110748_create_tables.rb
│   │   ├── 20250529110803_create_business_periods.rb
│   │   └── 20250529111701_create_reservations.rb
│   ├── seeds.rb                # 種子資料
│   └── schema.rb               # 資料庫結構定義
│
├── spec/                       # 測試檔案
│   ├── rails_helper.rb         # Rails 測試配置
│   ├── spec_helper.rb          # RSpec 配置
│   ├── models/                 # 模型測試
│   ├── controllers/            # 控制器測試
│   ├── services/               # 服務測試
│   ├── system/                 # 系統整合測試
│   ├── factories/              # 測試資料工廠
│   └── support/                # 測試輔助檔案
│
├── docs/                       # 文件目錄
│   ├── database_schema.md      # 資料庫關聯圖
│   ├── system_architecture.md # 系統架構圖
│   └── project_structure.md   # 專案結構說明
│
├── lib/                        # 自定義函式庫
│   └── tasks/                  # 自定義 Rake 任務
│
├── public/                     # 靜態檔案
│   ├── 404.html                # 錯誤頁面
│   ├── 422.html
│   ├── 500.html
│   └── robots.txt              # 搜尋引擎爬蟲設定
│
├── storage/                    # 檔案儲存
├── tmp/                        # 暫存檔案
├── log/                        # 日誌檔案
├── vendor/                     # 第三方程式庫
└── node_modules/               # Node.js 依賴套件
```

## 核心目錄說明

### app/ - 應用程式核心

這是 Rails 應用程式的主要程式碼目錄，遵循 MVC 架構模式：

#### controllers/ - 控制器層

-   **application_controller.rb**: 基礎控制器，包含認證和授權邏輯
-   **admin/**: 管理後台控制器，處理後台管理功能
-   **api/**: API 控制器，提供 RESTful API 服務

#### models/ - 模型層

-   遵循 7 個區塊結構的 ActiveRecord 模型
-   包含完整的驗證、關聯和業務邏輯
-   **concerns/**: 共用模組，實現程式碼重用

#### views/ - 視圖層

-   使用 ERB 模板引擎
-   支援 Turbo 和 Stimulus 的現代化前端體驗
-   **layouts/**: 版面配置檔案
-   **shared/**: 可重用的視圖組件

#### services/ - 服務層

-   封裝複雜的業務邏輯
-   提供事務處理和錯誤處理
-   遵循單一職責原則

### config/ - 配置管理

-   **routes.rb**: 定義應用程式的 URL 路由
-   **database.yml**: 資料庫連接配置
-   **environments/**: 不同環境的特定配置
-   **initializers/**: 應用程式啟動時的初始化設定

### db/ - 資料庫管理

-   **migrate/**: 資料庫遷移檔案，版本控制資料庫結構
-   **seeds.rb**: 種子資料，用於初始化示範資料
-   **schema.rb**: 當前資料庫結構的快照

### spec/ - 測試套件

-   使用 RSpec 測試框架
-   包含單元測試、整合測試和系統測試
-   **factories/**: FactoryBot 測試資料工廠
-   **support/**: 測試輔助檔案和共用設定

### docs/ - 文件系統

-   包含系統設計文件和技術文件
-   使用 Mermaid 圖表展示系統架構
-   提供開發和維護指南

## 檔案命名慣例

### Ruby 檔案

-   使用 snake_case 命名
-   模型檔案使用單數形式 (user.rb, reservation.rb)
-   控制器檔案使用複數形式 (users_controller.rb)

### 視圖檔案

-   使用 snake_case 命名
-   對應控制器動作名稱 (index.html.erb, show.html.erb)
-   部分視圖以底線開頭 (\_form.html.erb)

### 測試檔案

-   在檔案名稱後加上 \_spec.rb
-   目錄結構對應 app/ 目錄結構

## 程式碼組織原則

### 1. 關注點分離

-   控制器只處理 HTTP 請求和回應
-   模型包含資料邏輯和驗證
-   服務層處理複雜業務邏輯

### 2. 單一職責

-   每個類別和方法只負責一個功能
-   避免過大的檔案和方法

### 3. 依賴注入

-   服務類別通過建構函數接收依賴
-   便於測試和維護

### 4. 配置管理

-   環境特定配置放在對應的環境檔案中
-   敏感資訊使用環境變數

## 開發工作流程

### 1. 新功能開發

```
1. 建立遷移檔案 (rails generate migration)
2. 建立/修改模型
3. 建立/修改控制器
4. 建立/修改視圖
5. 建立/修改服務 (如需要)
6. 撰寫測試
7. 執行測試確保通過
```

### 2. 測試驅動開發 (TDD)

```
1. 撰寫失敗的測試
2. 實作最小可行程式碼
3. 重構改善程式碼品質
4. 重複循環
```

### 3. 程式碼審查

```
1. 檢查程式碼品質
2. 確保測試覆蓋率
3. 驗證安全性
4. 檢查效能影響
```

這個專案結構設計旨在提供清晰的程式碼組織、良好的可維護性和高品質的開發體驗。
