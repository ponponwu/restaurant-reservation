# 餐廳訂位系統 - 系統架構

## 系統架構圖

```mermaid
graph TB
    subgraph "前端層 (Frontend)"
        UI[用戶介面]
        Admin[管理後台]
        API_Client[API 客戶端]
    end

    subgraph "控制器層 (Controllers)"
        AuthC[認證控制器]
        AdminC[管理控制器]
        ReservationC[訂位控制器]
        TableC[桌位控制器]
    end

    subgraph "服務層 (Services)"
        ReservationS[訂位服務]
        TableS[桌位服務]
        NotificationS[通知服務]
    end

    subgraph "模型層 (Models)"
        User[用戶模型]
        Restaurant[餐廳模型]
        Table[桌位模型]
        Reservation[訂位模型]
        BusinessPeriod[營業時段模型]
        TableGroup[桌位群組模型]
    end

    subgraph "資料庫層 (Database)"
        PostgreSQL[(PostgreSQL)]
    end

    %% 連接關係
    UI --> AuthC
    Admin --> AdminC
    API_Client --> ReservationC

    AuthC --> User
    AdminC --> ReservationS
    ReservationC --> ReservationS
    TableC --> TableS

    ReservationS --> Reservation
    ReservationS --> Table
    ReservationS --> NotificationS
    TableS --> Table
    TableS --> TableGroup

    User --> PostgreSQL
    Restaurant --> PostgreSQL
    Table --> PostgreSQL
    Reservation --> PostgreSQL
    BusinessPeriod --> PostgreSQL
    TableGroup --> PostgreSQL
```

## 核心功能模組

### 1. 認證與授權模組

```mermaid
graph LR
    Login[登入] --> Devise[Devise 認證]
    Devise --> CanCan[CanCanCan 授權]
    CanCan --> Role{角色檢查}
    Role --> Admin[管理員]
    Role --> Manager[經理]
    Role --> Staff[員工]
```

### 2. 訂位管理模組

```mermaid
graph TD
    CreateReservation[建立訂位] --> ValidateInput[驗證輸入]
    ValidateInput --> CheckAvailability[檢查可用性]
    CheckAvailability --> AssignTable[分配桌位]
    AssignTable --> SendConfirmation[發送確認]

    ModifyReservation[修改訂位] --> CheckPermission[檢查權限]
    CheckPermission --> UpdateDetails[更新詳情]
    UpdateDetails --> NotifyChanges[通知變更]

    CancelReservation[取消訂位] --> ValidateCancel[驗證可取消]
    ValidateCancel --> ReleaseTable[釋放桌位]
    ReleaseTable --> SendCancellation[發送取消通知]
```

### 3. 桌位管理模組

```mermaid
graph TD
    TableManagement[桌位管理] --> CreateTable[建立桌位]
    TableManagement --> UpdateStatus[更新狀態]
    TableManagement --> CheckAvailability[檢查可用性]

    CreateTable --> SetCapacity[設定容量]
    CreateTable --> AssignGroup[分配群組]

    UpdateStatus --> Available[可用]
    UpdateStatus --> Occupied[佔用]
    UpdateStatus --> Maintenance[維護]

    CheckAvailability --> TimeSlot[時段檢查]
    CheckAvailability --> Capacity[容量檢查]
```

## 技術棧

### 後端技術

-   **框架**: Ruby on Rails 7.1
-   **資料庫**: PostgreSQL
-   **認證**: Devise
-   **授權**: CanCanCan
-   **背景任務**: Sidekiq
-   **API**: RESTful API

### 前端技術

-   **框架**: Hotwire (Turbo + Stimulus)
-   **樣式**: Bootstrap 5
-   **建構工具**: esbuild
-   **即時更新**: Turbo Streams

### 開發工具

-   **測試**: RSpec + FactoryBot + Capybara
-   **程式碼品質**: RuboCop
-   **安全檢查**: Brakeman
-   **依賴管理**: Bundler

## 資料流程

### 訂位建立流程

```mermaid
sequenceDiagram
    participant C as 客戶
    participant UI as 前端介面
    participant RC as 訂位控制器
    participant RS as 訂位服務
    participant DB as 資料庫
    participant NS as 通知服務

    C->>UI: 填寫訂位表單
    UI->>RC: 提交訂位請求
    RC->>RS: 呼叫建立訂位服務
    RS->>DB: 檢查桌位可用性
    DB-->>RS: 回傳可用桌位
    RS->>DB: 建立訂位記錄
    DB-->>RS: 確認建立成功
    RS->>NS: 發送確認通知
    NS-->>C: 發送確認簡訊/郵件
    RS-->>RC: 回傳建立結果
    RC-->>UI: 回傳成功回應
    UI-->>C: 顯示訂位確認
```

### 桌位狀態更新流程

```mermaid
sequenceDiagram
    participant S as 員工
    participant AC as 管理控制器
    participant TS as 桌位服務
    participant DB as 資料庫
    participant WS as WebSocket

    S->>AC: 更新桌位狀態
    AC->>TS: 呼叫狀態更新服務
    TS->>DB: 更新桌位狀態
    DB-->>TS: 確認更新成功
    TS->>WS: 廣播狀態變更
    WS-->>S: 即時更新介面
    TS-->>AC: 回傳更新結果
    AC-->>S: 顯示更新成功
```

## 安全性設計

### 認證安全

-   使用 Devise 進行用戶認證
-   密碼加密儲存
-   會話管理和超時控制

### 授權控制

-   基於角色的權限控制 (RBAC)
-   資源層級的權限檢查
-   API 端點權限驗證

### 資料安全

-   SQL 注入防護 (ActiveRecord)
-   XSS 防護 (Rails 內建)
-   CSRF 保護
-   敏感資料加密

## 效能優化

### 資料庫優化

-   適當的索引設計
-   查詢優化 (避免 N+1)
-   連接池管理

### 快取策略

-   頁面片段快取
-   查詢結果快取
-   靜態資源快取

### 前端優化

-   資源壓縮和合併
-   圖片優化
-   懶載入技術

## 監控與日誌

### 應用監控

-   效能監控
-   錯誤追蹤
-   使用者行為分析

### 日誌管理

-   結構化日誌
-   日誌等級管理
-   日誌輪轉和保存

### 健康檢查

-   資料庫連接檢查
-   外部服務檢查
-   系統資源監控
