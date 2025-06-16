# ReservationsController 重構總結

## 問題分析

原始的 `ReservationsController` 存在以下問題：

1. **不當的快取策略**：使用 2 分鐘的短期快取來"減少 race condition"，這是治標不治本的解決方案
2. **複雜的 create 方法**：單一方法包含太多職責，難以維護和測試
3. **重複的可用性檢查邏輯**：多個方法包含相似的可用性檢查程式碼
4. **快取鍵不完整**：沒有包含所有影響可用性的因子（如營業時間變更）

## 重構解決方案

### 1. 改善快取策略

**之前**：

```ruby
cache_key = "availability_status:#{@restaurant.id}:#{Date.current}:#{party_size}:v3"
result = Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
  # 複雜的可用性計算
end
```

**之後**：

```ruby
cache_key = build_availability_cache_key(party_size)
result = Rails.cache.fetch(cache_key, expires_in: 15.minutes) do
  calculate_availability_status(party_size, has_capacity)
end

def build_availability_cache_key(party_size)
  restaurant_updated_at = [@restaurant.updated_at,
                         @restaurant.reservation_policy&.updated_at,
                         @restaurant.business_periods.maximum(:updated_at)].compact.max

  "availability_status:#{@restaurant.id}:#{Date.current}:#{party_size}:#{restaurant_updated_at.to_i}:v4"
end
```

**改進**：

-   使用更長的快取時間（15 分鐘）提高效能
-   快取鍵包含餐廳設定的更新時間，確保設定變更時快取自動失效
-   移除依賴短期快取來解決併發問題的錯誤做法

### 2. 重構併發控制

**之前**：依賴短期快取 + ReservationLockService

**之後**：完全依賴 ReservationLockService 進行併發控制

```ruby
def create_reservation_with_concurrency_control
  begin
    ReservationLockService.with_lock(@restaurant.id, @reservation.reservation_datetime, @reservation.party_size) do
      ActiveRecord::Base.transaction do
        allocate_table_and_save_reservation
      end
    end
  rescue ConcurrentReservationError => e
    { success: false, errors: [e.message] }
  end
end
```

**改進**：

-   使用適當的鎖定機制而非快取來解決併發問題
-   更清晰的錯誤處理和回傳結構

### 3. 分解複雜方法

**之前**：`create` 方法包含 80+ 行程式碼，處理多個職責

**之後**：分解為多個專注的方法

```ruby
def create
  return unless validate_reservation_enabled

  @reservation = build_reservation
  setup_create_params

  return unless validate_phone_booking_limit

  result = create_reservation_with_concurrency_control

  if result[:success]
    redirect_to restaurant_public_path(@restaurant.slug), notice: '訂位建立成功！'
  else
    handle_reservation_creation_failure(result[:errors])
  end
end
```

**新增的專注方法**：

-   `validate_reservation_enabled`
-   `build_reservation`
-   `setup_create_params`
-   `validate_phone_booking_limit`
-   `create_reservation_with_concurrency_control`
-   `allocate_table_and_save_reservation`
-   `save_reservation_with_table`
-   `handle_reservation_creation_failure`

### 4. 創建 AvailabilityService

將重複的可用性檢查邏輯整合到專門的服務類別：

```ruby
class AvailabilityService
  def initialize(restaurant)
    @restaurant = restaurant
  end

  def has_any_availability_on_date?(date, party_size = 2)
    # 統一的可用性檢查邏輯
  end

  def get_available_slots_by_period(date, party_size, adults, children)
    # 統一的時間槽檢查邏輯
  end

  def check_availability_for_date_range(start_date, end_date, party_size = 2)
    # 批量日期範圍檢查，避免 N+1 查詢
  end
end
```

**改進**：

-   消除重複程式碼
-   更好的關注點分離
-   更容易測試和維護
-   優化的批量查詢避免 N+1 問題

### 5. 改善錯誤處理

**之前**：錯誤處理散布在各處，不一致的回傳格式

**之後**：統一的錯誤處理和回傳結構

```ruby
def create_reservation_with_concurrency_control
  # 統一的成功/失敗回傳格式
  { success: true } 或 { success: false, errors: [...] }
end

def handle_reservation_creation_failure(errors)
  errors.each { |error| @reservation.errors.add(:base, error) }
  @selected_date = Date.parse(params[:date]) rescue Date.current
  render :new, status: :unprocessable_entity
end
```

## 效能改進

1. **更長的快取時間**：從 2 分鐘增加到 15 分鐘，減少重複計算
2. **批量查詢優化**：`AvailabilityService` 使用批量查詢避免 N+1 問題
3. **智慧快取失效**：快取鍵包含相關設定的更新時間，確保資料一致性

## 安全性改進

1. **移除快取依賴的併發控制**：使用適當的鎖定機制
2. **更好的輸入驗證**：統一的參數解析和驗證
3. **一致的錯誤處理**：避免資訊洩漏

## 可維護性改進

1. **單一職責原則**：每個方法只處理一個職責
2. **更好的測試覆蓋**：小方法更容易測試
3. **清晰的程式碼結構**：邏輯流程更容易理解
4. **服務層分離**：業務邏輯從控制器中分離

## 測試策略

創建了完整的 `AvailabilityService` 測試，包括：

-   單元測試覆蓋所有公開方法
-   效能測試確保批量操作的效率
-   邊界條件測試
-   N+1 查詢防護測試

## 總結

這次重構解決了原始程式碼的主要問題：

1. ✅ **併發控制**：使用適當的鎖定機制而非快取
2. ✅ **快取策略**：更長的快取時間 + 智慧失效機制
3. ✅ **程式碼結構**：分解複雜方法，提高可維護性
4. ✅ **重複程式碼**：整合到專門的服務類別
5. ✅ **效能優化**：批量查詢和更好的快取策略
6. ✅ **測試覆蓋**：完整的測試確保程式碼品質

重構後的程式碼更加健壯、可維護，並且遵循 Rails 最佳實踐。
