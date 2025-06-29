# bin/rspec-fast 測試指南

## ✅ 修復完成

### 🔧 **問題與解決方案**
- **原問題**: Ruby script 導致 Rails 環境載入錯誤
- **解決方案**: 改用 bash script，避免複雜的 Ruby 環境載入
- **改進**: 新增更詳細的使用說明和錯誤處理

### 🚀 **現在可以使用的功能**

#### 基本測試指令
```bash
# 快速測試 (models) - ~30秒
bin/rspec-fast

# 中速測試 (services + requests) - ~2分鐘  
bin/rspec-fast medium

# 系統測試 (browser tests) - ~3-5分鐘
bin/rspec-fast slow

# 完整測試套件 - ~5-8分鐘
bin/rspec-fast all
```

#### 取得說明
```bash
# 顯示使用說明
bin/rspec-fast help
bin/rspec-fast --help
bin/rspec-fast invalid-option
```

### 🧪 **測試步驟**

#### 1. 基本功能測試
```bash
# 測試說明顯示
bin/rspec-fast help

# 測試各種選項 (如果你有時間)
bin/rspec-fast          # 應該顯示 fast tests 並執行 models
bin/rspec-fast medium   # 應該顯示 medium tests 並執行 services/requests  
bin/rspec-fast slow     # 應該顯示 system tests 並執行 system
bin/rspec-fast all      # 應該顯示 all tests 並執行全部
```

#### 2. 錯誤處理測試
```bash
# 測試無效參數
bin/rspec-fast invalid-param   # 應該顯示使用說明並退出
```

### 📊 **預期結果**

#### ✅ **成功指標**
- 腳本啟動無錯誤訊息
- 正確顯示表情符號和說明文字
- RSpec 開始執行並顯示測試結果
- 無 Ruby 載入錯誤

#### ❌ **需要注意的警告**
- `DidYouMean::SPELL_CHECKERS` deprecation 警告 (正常，可忽略)
- `tzinfo-data` platform 警告 (正常，可忽略)

### 🎯 **GitHub CI 兼容性**

現在的腳本完全兼容 GitHub Actions：
```yaml
# CI 中的使用方式
- name: Run fast tests
  run: bin/rspec-fast

- name: Run medium tests  
  run: bin/rspec-fast medium

- name: Run system tests
  run: bin/rspec-fast slow
```

### 🐛 **如果還有問題**

如果仍然遇到問題，可能的原因和解決方案：

1. **權限問題**
   ```bash
   chmod +x bin/rspec-fast
   ```

2. **Bundle 環境問題**
   ```bash
   bundle install
   bundle exec rspec --version  # 測試基本 RSpec 功能
   ```

3. **Rails 環境問題**
   ```bash
   bundle exec rails runner "puts 'Rails OK'"  # 測試 Rails 載入
   ```

---

**🎉 修復完成！現在你可以享受快速且穩定的測試執行了！**