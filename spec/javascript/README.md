# JavaScript 測試設定說明

## 設定 Jest 進行 JavaScript 控制器測試

### 1. 安裝必要的依賴

```bash
npm install --save-dev jest jest-environment-jsdom @babel/preset-env
```

### 2. 在 package.json 中添加測試腳本

```json
{
  "scripts": {
    "test:js": "jest",
    "test:js:watch": "jest --watch",
    "test:js:coverage": "jest --coverage"
  },
  "jest": {
    "testEnvironment": "jsdom",
    "setupFilesAfterEnv": ["<rootDir>/spec/javascript/setup.js"],
    "moduleNameMapper": {
      "^@hotwired/stimulus$": "<rootDir>/spec/javascript/mocks/stimulus.js",
      "^flatpickr$": "<rootDir>/spec/javascript/mocks/flatpickr.js",
      "^flatpickr/dist/l10n/zh-tw.js$": "<rootDir>/spec/javascript/mocks/flatpickr.js"
    },
    "testMatch": ["<rootDir>/spec/javascript/**/*_spec.js"],
    "collectCoverageFrom": [
      "app/javascript/controllers/**/*.js",
      "!app/javascript/controllers/index.js"
    ]
  }
}
```

### 3. 執行測試

```bash
# 執行所有 JavaScript 測試
npm run test:js

# 監視模式執行測試
npm run test:js:watch

# 生成測試覆蓋率報告
npm run test:js:coverage

# 執行特定測試檔案
npx jest spec/javascript/admin_reservation_controller_spec.js
```

## 測試檔案說明

### admin_reservation_controller_spec.js
測試後台訂位控制器的 JavaScript 邏輯：
- `calculateAdminDisabledDates` - 計算管理員模式下的禁用日期
- `fetchDisabledDates` - 獲取休息日資訊的 API 呼叫
- `getCurrentPartySize` - 獲取當前人數設定
- 錯誤處理和邊界情況

### 系統測試
- `admin_reservation_calendar_spec.rb` - 測試日曆 UI 互動
- `admin_reservation_flow_with_closures_spec.rb` - 測試完整訂位流程
- `admin_available_days_spec.rb` - 測試 API 端點

## Mock 說明

### flatpickr.js
模擬 flatpickr 日期選擇器庫的行為，包括：
- 基本的日期選擇器方法
- 語言包支援
- 配置選項

### stimulus.js
模擬 Stimulus 控制器基類，提供：
- 基本的控制器生命週期方法
- Target 和 Value 系統
- DOM 元素綁定

## 測試策略

1. **單元測試**：測試個別 JavaScript 方法的邏輯
2. **集成測試**：測試控制器與 DOM 的互動
3. **系統測試**：測試完整的用戶流程
4. **API 測試**：驗證後端 API 的回應格式

## 注意事項

- 所有測試都使用固定的時間 (2025-06-20) 確保結果一致
- Mock 設定確保測試不依賴外部服務
- 測試涵蓋正常情況、錯誤情況和邊界情況
- 系統測試使用真實的瀏覽器環境驗證 UI 行為