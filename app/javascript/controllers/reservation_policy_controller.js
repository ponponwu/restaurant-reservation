import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = [
        'checkbox',
        'toggle',
        'toggleButton',
        'status',
        'settings',
        'depositCheckbox',
        'depositFields',
        'unlimitedCheckbox',
        'limitedTimeSettings',
        'diningDurationField',
        'durationPreview',
        'examplePreview',
    ]
    static values = { enabled: Boolean }

    connect() {
        console.log('🔧 ReservationPolicy controller connected')
        this.updateUI()
        this.initializeDeposit()
        this.initializeDiningTime()
        this.updateDiningTimePreview()
    }

    // 處理切換開關點擊
    toggle(event) {
        event.preventDefault()
        console.log('🔧 切換開關被點擊')

        // 切換 checkbox 狀態
        this.checkboxTarget.checked = !this.checkboxTarget.checked
        console.log('🔧 新的 checkbox 狀態:', this.checkboxTarget.checked)

        // 更新 UI
        this.updateUI()

        // 提交表單
        this.submitForm()
    }

    // 處理 checkbox 變更事件
    checkboxChanged() {
        console.log('🔧 checkbox change 事件觸發')
        this.updateUI()
        this.submitForm()
    }

    // 更新UI狀態
    updateUI() {
        const enabled = this.checkboxTarget.checked
        console.log('🔧 更新UI狀態為:', enabled)

        if (enabled) {
            this.enableReservation()
        } else {
            this.disableReservation()
        }
    }

    // 啟用訂位功能的UI
    enableReservation() {
        console.log('🔧 設定為啟用狀態')

        // 更新設定區域
        if (this.hasSettingsTarget) {
            this.settingsTarget.classList.remove('opacity-50', 'pointer-events-none')
        }

        // 更新切換開關樣式
        if (this.hasToggleTarget) {
            this.toggleTarget.classList.remove('bg-gray-200')
            this.toggleTarget.classList.add('bg-blue-600')
        }

        // 更新切換按鈕位置
        if (this.hasToggleButtonTarget) {
            this.toggleButtonTarget.classList.remove('translate-x-0')
            this.toggleButtonTarget.classList.add('translate-x-5')
        }

        // 更新狀態文字
        if (this.hasStatusTarget) {
            this.statusTarget.textContent = '已啟用'
        }
    }

    // 停用訂位功能的UI
    disableReservation() {
        console.log('🔧 設定為停用狀態')

        // 更新設定區域
        if (this.hasSettingsTarget) {
            this.settingsTarget.classList.add('opacity-50', 'pointer-events-none')
        }

        // 更新切換開關樣式
        if (this.hasToggleTarget) {
            this.toggleTarget.classList.remove('bg-blue-600')
            this.toggleTarget.classList.add('bg-gray-200')
        }

        // 更新切換按鈕位置
        if (this.hasToggleButtonTarget) {
            this.toggleButtonTarget.classList.remove('translate-x-5')
            this.toggleButtonTarget.classList.add('translate-x-0')
        }

        // 更新狀態文字
        if (this.hasStatusTarget) {
            this.statusTarget.textContent = '已停用'
        }
    }

    // 提交表單
    submitForm() {
        const form = document.getElementById('reservation_policy_form')
        if (form) {
            console.log('🔧 提交表單')
            form.requestSubmit()
        } else {
            console.error('🔧 找不到表單')
        }
    }

    // 處理押金設定切換
    toggleDeposit(event) {
        const enabled = event.target.checked
        console.log('🔧 押金設定切換為:', enabled)

        if (this.hasDepositFieldsTarget) {
            if (enabled) {
                this.depositFieldsTarget.classList.remove('hidden')
            } else {
                this.depositFieldsTarget.classList.add('hidden')
            }
        }
    }

    // 初始化押金設定顯示狀態
    initializeDeposit() {
        if (this.hasDepositCheckboxTarget && this.hasDepositFieldsTarget) {
            const isEnabled = this.depositCheckboxTarget.checked
            console.log('🔧 初始化押金設定狀態:', isEnabled)

            if (!isEnabled) {
                this.depositFieldsTarget.classList.add('hidden')
            } else {
                this.depositFieldsTarget.classList.remove('hidden')
            }
        }
    }

    // 處理無限用餐時間切換
    toggleUnlimitedTime(event) {
        const unlimited = event.target.checked
        console.log('🔧 無限用餐時間切換為:', unlimited)

        if (this.hasLimitedTimeSettingsTarget) {
            if (unlimited) {
                this.limitedTimeSettingsTarget.classList.add('opacity-50', 'pointer-events-none')
            } else {
                this.limitedTimeSettingsTarget.classList.remove('opacity-50', 'pointer-events-none')
            }
        }

        this.updateDiningTimePreview()
    }

    // 初始化用餐時間設定
    initializeDiningTime() {
        if (this.hasUnlimitedCheckboxTarget && this.hasLimitedTimeSettingsTarget) {
            const unlimited = this.unlimitedCheckboxTarget.checked
            console.log('🔧 初始化用餐時間設定:', unlimited ? '無限時' : '有限時')

            if (unlimited) {
                this.limitedTimeSettingsTarget.classList.add('opacity-50', 'pointer-events-none')
            } else {
                this.limitedTimeSettingsTarget.classList.remove('opacity-50', 'pointer-events-none')
            }
        }
    }

    // 更新用餐時間預覽
    updateDiningTimePreview() {
        if (!this.hasDurationPreviewTarget || !this.hasExamplePreviewTarget) {
            return
        }

        if (this.hasUnlimitedCheckboxTarget && this.unlimitedCheckboxTarget.checked) {
            this.durationPreviewTarget.innerHTML = '總佔用時間：<span class="font-medium text-yellow-600">無限制</span>'
            this.examplePreviewTarget.innerHTML =
                '例如：18:00 訂位，<span class="font-medium text-yellow-600">不限制用餐時間</span>'
            return
        }

        const diningMinutes = this.hasDiningDurationFieldTarget
            ? parseInt(this.diningDurationFieldTarget.value) || 120
            : 120

        const totalMinutes = diningMinutes
        const hours = Math.floor(totalMinutes / 60)
        const minutes = totalMinutes % 60

        let durationText
        if (hours > 0 && minutes > 0) {
            durationText = `${hours}小時${minutes}分鐘`
        } else if (hours > 0) {
            durationText = `${hours}小時`
        } else {
            durationText = `${minutes}分鐘`
        }

        // 計算結束時間示例（18:00 + 總時長）
        const exampleStart = new Date()
        exampleStart.setHours(18, 0, 0, 0)
        const exampleEnd = new Date(exampleStart.getTime() + totalMinutes * 60000)
        const endTimeString = exampleEnd.toLocaleTimeString('zh-TW', {
            hour: '2-digit',
            minute: '2-digit',
            hour12: false,
        })

        this.durationPreviewTarget.innerHTML = `用餐時間：<span class="font-medium text-blue-600">${durationText}</span>`
        this.examplePreviewTarget.innerHTML = `例如：18:00 訂位，預計 <span class="font-medium text-blue-600">${endTimeString}</span> 用餐結束`
    }
}
