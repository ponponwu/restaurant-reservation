import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = []
    static values = {
        restaurantSlug: String
    }

    static identifier = 'special-dates'

    connect() {
        console.log('SpecialDates controller connected')
        
        // 綁定事件監聽器
        this.boundTurboFrameLoad = this.handleTurboFrameLoad.bind(this)
        this.boundBeforeStreamAction = this.handleBeforeStreamAction.bind(this)

        // 監聽 Turbo Stream 更新事件
        document.addEventListener('turbo:frame-load', this.boundTurboFrameLoad)
        document.addEventListener('turbo:before-stream-action', this.boundBeforeStreamAction)
    }

    disconnect() {
        // 移除事件監聽器
        if (this.boundTurboFrameLoad) {
            document.removeEventListener('turbo:frame-load', this.boundTurboFrameLoad)
        }
        if (this.boundBeforeStreamAction) {
            document.removeEventListener('turbo:before-stream-action', this.boundBeforeStreamAction)
        }
    }

    handleTurboFrameLoad(event) {
        // 當 modal 載入後的處理
        if (event.target.id === 'modal') {
            console.log('Modal loaded for special dates')
        }
    }

    handleBeforeStreamAction(event) {
        // Turbo Stream 動作執行前的處理
        console.log('Turbo stream action:', event.detail.action)
    }
}