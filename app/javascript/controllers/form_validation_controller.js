import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = ['nameInput', 'validationMessage']
    static values = { 
        restaurantId: String,
        currentName: String // 用於編輯時排除當前記錄
    }
    
    connect() {
        console.log('🔥 Form validation controller connected')
        this.debounceTimer = null
    }
    
    validateName() {
        const name = this.nameInputTarget.value.trim()
        
        // 清除之前的計時器
        if (this.debounceTimer) {
            clearTimeout(this.debounceTimer)
        }
        
        // 如果是空值或與當前名稱相同，清除驗證訊息
        if (!name || name === this.currentNameValue) {
            this.clearValidationMessage()
            return
        }
        
        // 延遲驗證避免過度請求
        this.debounceTimer = setTimeout(() => {
            this.checkNameUniqueness(name)
        }, 500)
    }
    
    checkNameUniqueness(name) {
        const csrfToken = document.querySelector('[name="csrf-token"]').content
        
        fetch(`/admin/restaurants/${this.restaurantIdValue}/table_groups/check_name_uniqueness`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': csrfToken,
            },
            body: JSON.stringify({
                name: name,
                current_name: this.currentNameValue
            })
        })
        .then(response => response.json())
        .then(data => {
            if (data.unique) {
                this.showValidationMessage('名稱可用', 'success')
            } else {
                this.showValidationMessage('該名稱已存在，請使用其他名稱', 'error')
            }
        })
        .catch(error => {
            console.error('🔥 Validation error:', error)
            this.clearValidationMessage()
        })
    }
    
    showValidationMessage(message, type) {
        const messageElement = this.validationMessageTarget
        const isError = type === 'error'
        
        messageElement.textContent = message
        messageElement.className = `mt-1 text-sm ${isError ? 'text-red-600' : 'text-green-600'}`
        messageElement.style.display = 'block'
        
        // 更新輸入框樣式
        this.nameInputTarget.className = this.nameInputTarget.className.replace(
            /border-gray-300|border-red-300|border-green-300/,
            isError ? 'border-red-300' : 'border-green-300'
        )
        
        // 更新提交按鈕狀態
        const submitButton = this.element.querySelector('input[type="submit"]')
        if (submitButton) {
            submitButton.disabled = isError
            submitButton.className = submitButton.className.replace(
                /bg-blue-600|bg-gray-400/,
                isError ? 'bg-gray-400' : 'bg-blue-600'
            )
        }
    }
    
    clearValidationMessage() {
        const messageElement = this.validationMessageTarget
        messageElement.style.display = 'none'
        messageElement.textContent = ''
        
        // 重置輸入框樣式
        this.nameInputTarget.className = this.nameInputTarget.className.replace(
            /border-red-300|border-green-300/,
            'border-gray-300'
        )
        
        // 重置提交按鈕狀態
        const submitButton = this.element.querySelector('input[type="submit"]')
        if (submitButton) {
            submitButton.disabled = false
            submitButton.className = submitButton.className.replace(
                /bg-gray-400/,
                'bg-blue-600'
            )
        }
    }
}