# 桌位狀態重構提案

## 🎯 問題識別

目前的桌位狀態設計存在邏輯冗餘：

### 現況問題

1. **資料不一致風險**: 桌位狀態和訂位記錄可能不同步
2. **維護複雜度**: 需要同時更新桌位狀態和訂位記錄
3. **邏輯混亂**: `occupied`/`reserved` 狀態和訂位記錄重複表達同一概念

### 當前狀態使用分析

```ruby
# 目前的狀態
enum status: {
  available: 'available',    # ❌ 冗餘 - 可透過訂位記錄判斷
  occupied: 'occupied',      # ❌ 冗餘 - 可透過訂位記錄判斷
  reserved: 'reserved',      # ❌ 冗餘 - 可透過訂位記錄判斷
  maintenance: 'maintenance', # ✅ 有意義 - 非訂位原因的不可用
  cleaning: 'cleaning'       # ✅ 有意義 - 非訂位原因的不可用
}
```

## 🚀 重構提案

### 方案 A：簡化狀態（推薦）

```ruby
# 簡化後的狀態
enum status: {
  normal: 'normal',           # 正常狀態（取代 available）
  maintenance: 'maintenance', # 維修中
  cleaning: 'cleaning',       # 清潔中
  out_of_service: 'out_of_service' # 停止服務
}

# 新的可用性判斷邏輯
def available_for_datetime?(datetime, duration_minutes = 120)
  # 1. 檢查桌位本身狀態
  return false unless normal? && active?

  # 2. 檢查訂位衝突
  end_time = datetime + duration_minutes.minutes
  conflicting_reservations = reservations.where(status: ['confirmed', 'seated'])
                                        .where("reservation_datetime < ? AND reservation_datetime + INTERVAL '#{duration_minutes} minutes' > ?",
                                               end_time, datetime)
  conflicting_reservations.empty?
end
```

### 方案 B：完全移除狀態

```ruby
# 移除 status 欄位，新增 operational_status
enum operational_status: {
  normal: 'normal',
  maintenance: 'maintenance',
  cleaning: 'cleaning',
  out_of_service: 'out_of_service'
}

# 簡化的可用性判斷
def available_for_datetime?(datetime, duration_minutes = 120)
  return false unless normal? && active?

  # 純粹透過訂位記錄判斷
  !has_conflicting_reservation?(datetime, duration_minutes)
end
```

## 📊 重構效益

### 資料一致性

-   ✅ 單一資料來源：訂位記錄
-   ✅ 減少資料不同步風險
-   ✅ 邏輯更清晰

### 程式碼簡化

```ruby
# 重構前：需要同時維護兩處
reservation.update!(status: 'confirmed')
table.update!(status: 'occupied')  # ❌ 冗餘

# 重構後：只需維護訂位記錄
reservation.update!(status: 'confirmed')  # ✅ 單一來源
```

### 查詢效能

```ruby
# 重構前：需要檢查桌位狀態 + 訂位記錄
available_tables = tables.where(status: 'available')
                        .select { |table| table.available_for_datetime?(time) }

# 重構後：統一邏輯，可能更好的索引利用
available_tables = tables.where(operational_status: 'normal', active: true)
                        .select { |table| table.available_for_datetime?(time) }
```

## 🔄 遷移策略

### 階段 1：準備階段

1. 新增 `operational_status` 欄位
2. 建立資料遷移腳本
3. 更新相關模型和驗證

### 階段 2：過渡階段

1. 同時支援舊 `status` 和新 `operational_status`
2. 逐步更新業務邏輯使用新欄位
3. 更新測試套件

### 階段 3：完成階段

1. 移除舊的 `status` 相關邏輯
2. 刪除冗餘欄位
3. 清理程式碼和文件

## 🧪 測試影響

### 需要更新的測試

-   桌位可用性測試
-   訂位分配測試
-   狀態變更相關測試

### 測試案例重點

```ruby
# 重構後的測試重點
describe 'table availability' do
  it '正常桌位在無訂位衝突時可用' do
    table = create(:table, operational_status: 'normal')
    expect(table.available_for_datetime?(1.hour.from_now)).to be true
  end

  it '維修中桌位不可用' do
    table = create(:table, operational_status: 'maintenance')
    expect(table.available_for_datetime?(1.hour.from_now)).to be false
  end

  it '有訂位衝突時不可用' do
    table = create(:table, operational_status: 'normal')
    create(:reservation, table: table, reservation_datetime: 1.hour.from_now)
    expect(table.available_for_datetime?(1.hour.from_now)).to be false
  end
end
```

## 🎯 建議

**採用方案 A（簡化狀態）**，原因：

1. 漸進式改進，風險較低
2. 保留有意義的狀態（maintenance、cleaning）
3. 移除冗餘狀態（occupied、reserved）
4. 為未來完全移除狀態預留空間

這個重構將使系統邏輯更清晰，減少維護複雜度，並提高資料一致性。
