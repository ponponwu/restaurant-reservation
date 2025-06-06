# 餐廳訂位系統 (Restaurant Reservation System)

一個使用 Ruby on Rails 7 和 Hotwire 技術建構的現代化餐廳訂位管理系統。

## 🚀 功能特色

### 核心功能

-   **用戶管理**: 支援管理員、經理、員工三種角色
-   **餐廳管理**: 完整的餐廳資訊和設定管理
-   **桌位管理**: 靈活的桌位群組和桌位配置
-   **訂位管理**: 完整的訂位生命週期管理
-   **營業時段**: 彈性的營業時間設定

### 技術特色

-   **現代化前端**: 使用 Hotwire (Turbo + Stimulus) 實現 SPA 體驗
-   **即時更新**: Turbo Streams 提供即時狀態同步
-   **響應式設計**: Bootstrap 5 確保跨裝置相容性
-   **安全性**: 完整的認證授權機制
-   **測試覆蓋**: 高品質的測試套件

## 🛠️ 技術棧

### 後端

-   **Ruby on Rails 7.1** - 主要框架
-   **PostgreSQL** - 資料庫
-   **Devise** - 用戶認證
-   **CanCanCan** - 權限管理
-   **Sidekiq** - 背景任務處理

### 前端

-   **Hotwire** - Turbo + Stimulus
-   **Bootstrap 5** - UI 框架
-   **esbuild** - JavaScript 建構工具

### 開發工具

-   **RSpec** - 測試框架
-   **FactoryBot** - 測試資料工廠
-   **Capybara** - 整合測試
-   **RuboCop** - 程式碼品質檢查

## 📋 系統需求

-   Ruby 2.7.7+
-   Rails 7.1+
-   PostgreSQL 12+
-   Node.js 16+ (用於前端資源建構)

## 🚀 快速開始

### 1. 複製專案

```bash
git clone <repository-url>
cd restaurant-reservation
```

### 2. 安裝依賴

```bash
# 安裝 Ruby gems
bundle install

# 安裝 Node.js 套件
npm install
```

### 3. 設定資料庫

```bash
# 建立資料庫
rails db:create

# 執行遷移
rails db:migrate

# 載入種子資料
rails db:seed
```

### 4. 啟動服務

```bash
# 啟動 Rails 伺服器
rails server

# 在另一個終端啟動 Sidekiq (背景任務)
bundle exec sidekiq
```

### 5. 訪問應用

開啟瀏覽器訪問 `http://localhost:3000`

## 👥 預設帳號

系統預設建立了以下測試帳號：

| 角色   | 電子郵件               | 密碼        |
| ------ | ---------------------- | ----------- |
| 管理員 | admin@restaurant.com   | password123 |
| 經理   | manager@restaurant.com | password123 |
| 員工   | staff@restaurant.com   | password123 |

## 📊 資料庫架構

系統包含以下主要實體：

-   **User** - 用戶管理
-   **Restaurant** - 餐廳資訊
-   **TableGroup** - 桌位群組
-   **Table** - 桌位管理
-   **BusinessPeriod** - 營業時段
-   **Reservation** - 訂位記錄

詳細的資料庫關聯圖請參考 [docs/database_schema.md](docs/database_schema.md)

## 🏗️ 系統架構

系統採用分層架構設計：

-   **前端層**: Hotwire + Tailwind
-   **控制器層**: Rails Controllers
-   **服務層**: 業務邏輯封裝
-   **模型層**: ActiveRecord Models
-   **資料庫層**: PostgreSQL

詳細的系統架構請參考 [docs/system_architecture.md](docs/system_architecture.md)

## 🧪 測試

### 執行所有測試

```bash
bundle exec rspec
```

### 執行特定測試

```bash
# 模型測試
bundle exec rspec spec/models

# 控制器測試
bundle exec rspec spec/controllers

# 系統測試
bundle exec rspec spec/system
```

### 測試覆蓋率

```bash
# 生成覆蓋率報告
COVERAGE=true bundle exec rspec
```

## 📝 開發規範

本專案遵循嚴格的開發規範，包括：

-   **模型設計**: 7 個區塊結構（關聯、驗證、scope、枚舉、回調、實例方法、私有方法）
-   **控制器設計**: 標準 RESTful 設計模式
-   **服務層**: 業務邏輯封裝和錯誤處理
-   **測試要求**: 高覆蓋率的單元測試和整合測試
-   **安全性**: 完整的輸入驗證和權限檢查

詳細的開發規範請參考專案內的自訂指令文件。

## 🔧 配置

### 環境變數

建立 `.env` 檔案並設定以下變數：

```env
DATABASE_URL=postgresql://username:password@localhost/restaurant_reservation_development
REDIS_URL=redis://localhost:6379/0
SECRET_KEY_BASE=your_secret_key_base
```

### 餐廳設定

系統支援豐富的餐廳設定選項：

-   時區設定
-   訂位提前天數
-   訂位時長
-   自動分配桌位
-   通知設定
-   取消政策

## 📈 效能優化

-   **資料庫索引**: 針對常用查詢建立適當索引
-   **查詢優化**: 使用 `includes` 避免 N+1 查詢
-   **快取策略**: 頁面片段快取和查詢結果快取
-   **前端優化**: 資源壓縮和懶載入

## 🔒 安全性

-   **認證**: Devise 提供安全的用戶認證
-   **授權**: CanCanCan 實現細粒度權限控制
-   **輸入驗證**: 所有用戶輸入都經過嚴格驗證
-   **SQL 注入防護**: ActiveRecord 提供內建保護
-   **XSS 防護**: Rails 內建 XSS 保護機制

## 🚀 部署

### 生產環境部署

```bash
# 設定生產環境
RAILS_ENV=production rails db:create db:migrate

# 預編譯資源
RAILS_ENV=production rails assets:precompile

# 啟動應用
RAILS_ENV=production rails server
```

### Docker 部署

```bash
# 建構映像
docker build -t restaurant-reservation .

# 執行容器
docker run -p 3000:3000 restaurant-reservation
```

## 📚 API 文件

系統提供 RESTful API 供外部整合：

-   `GET /api/reservations` - 取得訂位列表
-   `POST /api/reservations` - 建立新訂位
-   `PUT /api/reservations/:id` - 更新訂位
-   `DELETE /api/reservations/:id` - 取消訂位

詳細的 API 文件請參考 `/api/docs`

## 🤝 貢獻指南

1. Fork 專案
2. 建立功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交變更 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 開啟 Pull Request

## 📄 授權條款

本專案採用 MIT 授權條款 - 詳見 [LICENSE](LICENSE) 檔案

## 📞 支援

如有問題或建議，請：

1. 開啟 GitHub Issue
2. 聯繫開發團隊
3. 查看文件和 FAQ

---

**餐廳訂位系統** - 讓餐廳管理更簡單、更高效！
