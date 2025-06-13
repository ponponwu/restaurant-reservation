import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static values = {
        message: String,
        type: String,
        autoHide: Boolean,
        redirectAfter: Boolean,
        hideDelay: Number,
    }

    connect() {
        console.log('�� Flash 控制器已連接!', {
            autoHide: this.autoHideValue,
            redirectAfter: this.redirectAfterValue,
            hideDelay: this.hideDelayValue,
        })

        this.showFlash()

        if (this.autoHideValue) {
            const delay = this.hideDelayValue || 800
            console.log(`⏰ 將在 ${delay}ms 後自動隱藏`)
            setTimeout(() => {
                this.hide()
            }, delay)
        }
    }

    showFlash() {
        console.log('✨ 顯示 Flash 動畫')
        // 添加淡入動畫
        this.element.style.opacity = '0'
        this.element.style.transform = 'translateX(100%)'
        this.element.style.transition = 'all 0.3s ease-out'

        // 延遲一點顯示動畫
        setTimeout(() => {
            this.element.style.opacity = '1'
            this.element.style.transform = 'translateX(0)'
        }, 100)
    }

    hide() {
        console.log('🚪 開始隱藏 Flash')
        this.element.style.transition = 'all 0.3s ease-in'
        this.element.style.opacity = '0'
        this.element.style.transform = 'translateX(100%)'

        setTimeout(() => {
            if (this.redirectAfterValue) {
                console.log('🔄 重新載入頁面')
                window.location.reload()
            } else {
                console.log('🗑️ 移除 Flash 元素')
                this.element.remove()
            }
        }, 300)
    }

    // 手動關閉按鈕
    close() {
        console.log('❌ 手動關閉 Flash')
        this.hide()
    }
}
