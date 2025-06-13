import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = [
        'unlimitedCheckbox',
        'limitedTimeSettings',
        'diningDurationField',
        'bufferTimeField',
        'durationPreview',
        'examplePreview',
    ]

    connect() {
        this.toggleUnlimitedTime()
        this.updatePreview()
    }

    toggleUnlimitedTime() {
        const isUnlimited = this.unlimitedCheckboxTarget.checked

        if (isUnlimited) {
            this.limitedTimeSettingsTarget.classList.add('opacity-50', 'pointer-events-none')
            this.durationPreviewTarget.innerHTML = `總佔用時間：<span class="font-medium text-yellow-600">無限制</span>`
            this.examplePreviewTarget.innerHTML = `例如：18:00 訂位，<span class="font-medium text-yellow-600">桌位不會自動釋放</span>`
        } else {
            this.limitedTimeSettingsTarget.classList.remove('opacity-50', 'pointer-events-none')
            this.updatePreview()
        }
    }

    updatePreview() {
        if (this.unlimitedCheckboxTarget.checked) {
            return // 無限時模式不需要更新預覽
        }

        const diningMinutes = parseInt(this.diningDurationFieldTarget.value) || 120
        const bufferMinutes = parseInt(this.bufferTimeFieldTarget.value) || 15
        const totalMinutes = diningMinutes + bufferMinutes

        // 計算結束時間（以 18:00 為例）
        const startTime = new Date()
        startTime.setHours(18, 0, 0, 0)
        const endTime = new Date(startTime.getTime() + totalMinutes * 60000)

        this.durationPreviewTarget.innerHTML = `總佔用時間：<span class="font-medium text-blue-600">${totalMinutes} 分鐘</span>`
        this.examplePreviewTarget.innerHTML = `例如：18:00 訂位，桌位會被佔用到 <span class="font-medium text-blue-600">${endTime
            .getHours()
            .toString()
            .padStart(2, '0')}:${endTime.getMinutes().toString().padStart(2, '0')}</span>`
    }
}
