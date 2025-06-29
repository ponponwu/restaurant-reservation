# 切換到優化 CI 流程指南

如果你想要完全使用新的優化測試流程，只需要做以下調整：

## 🔄 **一鍵切換步驟**

### 1. 重命名現有 CI 配置
```bash
mv .github/workflows/ci.yml .github/workflows/ci-legacy.yml
```

### 2. 啟用優化 CI 為主要流程  
```bash
# 不需要額外操作，optimized-tests.yml 已經配置好
# 會自動在所有 PR/Push 時觸發
```

### 3. 提交變更
```bash
git add .github/workflows/
git commit -m "switch to optimized CI workflow"
git push
```

## 📊 **效果對比**

### 原有流程
- **執行時間**: ~15-20分鐘
- **階段**: 單一長時間執行
- **反饋速度**: 慢

### 優化後流程  
- **執行時間**: ~2.5分鐘 (日常) / ~6分鐘 (完整)
- **階段**: 快速 → 中速 → 系統測試 (條件式)
- **反饋速度**: 快速

## 🔙 **如何回滾**

如果需要回到原有流程：
```bash
mv .github/workflows/ci-legacy.yml .github/workflows/ci.yml
# 可選：停用或刪除 optimized-tests.yml
```

## 🎯 **推薦做法**

1. **先測試一週** optimized-tests.yml (手動觸發)
2. **確認穩定後** 再進行完全切換
3. **保留 ci-legacy.yml** 作為重要發布時的完整驗證

---

**✨ 切換後你將享受到 70% 更快的 CI 反饋速度！**