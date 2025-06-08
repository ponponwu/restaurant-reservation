# 餐廳訂位系統 - Super Admin 模組

## 專案目標

建立一個簡單的管理員系統，讓 Super Admin 能夠管理系統內的管理員帳戶和餐廳資料。

## 核心功能

1. **管理員管理** - CRUD + 即時搜尋
2. **餐廳管理** - CRUD + 即時搜尋
3. **簡單 Dashboard** - 基礎統計

## 技術棧

-   Ruby on Rails 7.1
-   Devise (認證)
-   CanCanCan (權限)
-   Tailwind CSS (樣式)
-   Hotwire (Turbo + Stimulus)
-   PostgreSQL

## 角色設計

```
Super Admin (系統最高管理員)
└── Admin (餐廳管理員)
```

## 資料表結構

```ruby
# User (管理員)
# id, email, encrypted_password, first_name, last_name
# role :string (super_admin, admin)
# restaurant_id :bigint (optional, super_admin 不屬於餐廳)
# active :boolean, deleted_at :datetime

# Restaurant (餐廳)
# id, name, phone, address
# active :boolean, deleted_at :datetime
```

## 頁面結構

```
/admin (需要登入)
├── /dashboard (首頁)
├── /users (管理員管理)
└── /restaurants (餐廳管理)
```

## 開發優先級

1. 基礎設定 (Rails + gems)
2. 管理員 CRUD 功能
3. 餐廳 CRUD 功能
4. Dashboard 和 UI 美化
