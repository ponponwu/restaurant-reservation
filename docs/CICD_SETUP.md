# 餐廳訂位系統 CI/CD 設置指南

## 概述

本專案使用 GitHub Actions 實現完整的 CI/CD 流程，包括：

-   程式碼品質檢查
-   自動化測試
-   Docker 容器構建
-   自動部署到 staging 和 production 環境

## 工作流程

### 1. CI 流程 (`.github/workflows/ci.yml`)

#### 觸發條件

-   Push 到 `main`、`develop`、`feature/*` 分支
-   建立 Pull Request 到 `main` 或 `develop` 分支

#### 檢查項目

1. **程式碼品質檢查 (linting)**

    - RuboCop：Ruby 程式碼風格檢查
    - Brakeman：安全性漏洞掃描
    - Bundle Audit：依賴套件安全性檢查

2. **自動化測試 (test)**

    - RSpec 單元測試
    - 系統測試（使用 Capybara）
    - 資料庫測試

3. **Docker 構建測試 (docker-build)**
    - 驗證 Docker 映像可以正常構建

### 2. CD 流程 (`.github/workflows/deploy.yml`)

#### 觸發條件

-   Push 到 `main` 分支
-   手動觸發 (workflow_dispatch)

#### 部署流程

1. **Staging 部署**

    - 構建 Docker 映像
    - 推送到 Docker Registry
    - 部署到 staging 環境
    - 健康檢查

2. **Production 部署**
    - 等待 staging 部署成功
    - 建立資料庫備份
    - 構建 production Docker 映像
    - 部署到 production 環境
    - 健康檢查
    - 失敗時支援回滾

## 必要的 GitHub Secrets

在 GitHub Repository Settings > Secrets and variables > Actions 中設置以下機密資訊：

### Docker Registry

```
DOCKER_REGISTRY=your-registry.com
DOCKER_USERNAME=your-username
DOCKER_PASSWORD=your-password
```

### Staging 環境

```
SECRET_KEY_BASE_STAGING=your-staging-secret-key
STAGING_HOST=staging.your-domain.com
STAGING_USER=deploy
STAGING_SSH_KEY=your-private-ssh-key
STAGING_URL=https://staging.your-domain.com
```

### Production 環境

```
SECRET_KEY_BASE_PRODUCTION=your-production-secret-key
PRODUCTION_HOST=your-domain.com
PRODUCTION_USER=deploy
PRODUCTION_SSH_KEY=your-private-ssh-key
PRODUCTION_URL=https://your-domain.com
POSTGRES_USER=your-db-user
POSTGRES_PASSWORD=your-db-password
```

## 伺服器設置

### 1. 安裝 Docker 和 Docker Compose

```bash
# 更新套件
sudo apt update && sudo apt upgrade -y

# 安裝 Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# 安裝 Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 將使用者加入 docker 群組
sudo usermod -aG docker $USER
```

### 2. 建立部署目錄

```bash
sudo mkdir -p /opt/restaurant-reservation
sudo chown $USER:$USER /opt/restaurant-reservation
cd /opt/restaurant-reservation

# 下載 Docker Compose 檔案
wget https://raw.githubusercontent.com/your-username/restaurant-reservation/main/docker-compose.prod.yml
```

### 3. 環境變數設置

建立 `.env` 檔案：

```bash
cat > .env << EOL
RAILS_ENV=production
DOCKER_REGISTRY=your-registry.com
IMAGE_TAG=latest
SECRET_KEY_BASE=your-secret-key-base
POSTGRES_USER=your-db-user
POSTGRES_PASSWORD=your-db-password
EOL
```

### 4. 啟動服務

```bash
docker-compose -f docker-compose.prod.yml up -d
```

## 健康檢查

系統提供健康檢查端點：`/health`

回應格式：

```json
{
    "status": "healthy",
    "timestamp": "2024-01-01T12:00:00Z",
    "environment": "production",
    "version": "abc1234",
    "checks": {
        "database": {
            "status": "ok",
            "response_time_ms": 5.2
        },
        "redis": {
            "status": "ok",
            "response_time_ms": 1.8
        }
    }
}
```

## 監控和日誌

### 查看容器狀態

```bash
docker-compose -f docker-compose.prod.yml ps
```

### 查看日誌

```bash
# 查看所有服務日誌
docker-compose -f docker-compose.prod.yml logs

# 查看特定服務日誌
docker-compose -f docker-compose.prod.yml logs web
docker-compose -f docker-compose.prod.yml logs sidekiq
```

### 進入容器

```bash
# 進入 web 容器
docker-compose -f docker-compose.prod.yml exec web bash

# 執行 Rails console
docker-compose -f docker-compose.prod.yml exec web bundle exec rails console
```

## 資料庫管理

### 執行遷移

```bash
docker-compose -f docker-compose.prod.yml exec web bundle exec rails db:migrate
```

### 建立備份

```bash
docker-compose -f docker-compose.prod.yml exec db pg_dump -U postgres restaurant_reservation_production > backup_$(date +%Y%m%d_%H%M%S).sql
```

### 還原備份

```bash
docker-compose -f docker-compose.prod.yml exec -T db psql -U postgres restaurant_reservation_production < backup_file.sql
```

## 故障排除

### 常見問題

1. **健康檢查失敗**

    - 檢查資料庫連線
    - 檢查 Redis 連線
    - 查看應用程式日誌

2. **部署失敗**

    - 檢查 Docker 映像是否正確構建
    - 檢查環境變數設置
    - 檢查磁碟空間

3. **測試失敗**
    - 檢查測試資料庫設置
    - 檢查測試依賴是否正確安裝

### 回滾部署

如果需要手動回滾到上一個版本：

```bash
# 停止服務
docker-compose -f docker-compose.prod.yml down

# 使用上一個映像標籤
export IMAGE_TAG=previous-tag

# 重新啟動
docker-compose -f docker-compose.prod.yml up -d
```

## 效能優化

### CI 快取

-   Ruby gems 快取
-   Node.js modules 快取
-   Docker layer 快取

### 部署優化

-   零停機部署
-   健康檢查等待
-   資料庫自動備份

## 安全性

### 程式碼掃描

-   Brakeman 安全性掃描
-   Bundle Audit 依賴檢查
-   RuboCop 程式碼品質

### 部署安全性

-   SSH 金鑰認證
-   環境變數隔離
-   Docker 容器隔離

## 維護

### 定期任務

-   每週執行依賴更新檢查
-   每月檢查安全性更新
-   定期清理舊的 Docker 映像

### 監控指標

-   部署成功率
-   測試覆蓋率
-   健康檢查回應時間
