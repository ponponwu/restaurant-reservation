import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = [
        'weeklyForm',
        'specificForm',
        'allDayCheckbox',
        'timeFields',
        'weekdayLabel',
        'weekdayCheckbox',
        'weeklyPattern',
    ]
    static values = {
        restaurantSlug: String,
        closureDatesUrl: String,
    }

    static identifier = 'closure-dates'

    connect() {
        // 立即設定全域函數（為了向後相容）
        this.setupGlobalFunctions()

        // 綁定事件監聽器到當前實例
        this.boundTurboFrameLoad = this.handleTurboFrameLoad.bind(this)
        this.boundBeforeStreamAction = this.handleBeforeStreamAction.bind(this)

        // 監聽 Turbo Stream 更新事件，確保動態內容載入後重新初始化
        document.addEventListener('turbo:frame-load', this.boundTurboFrameLoad)
        document.addEventListener('turbo:before-stream-action', this.boundBeforeStreamAction)

        // 延遲初始化檢查，確保 DOM 完全載入
        setTimeout(() => {
            this.checkExistingClosureDates()
        }, 150)
    }

    disconnect() {
        // 移除事件監聽器（使用綁定的實例）
        if (this.boundTurboFrameLoad) {
            document.removeEventListener('turbo:frame-load', this.boundTurboFrameLoad)
        }
        if (this.boundBeforeStreamAction) {
            document.removeEventListener('turbo:before-stream-action', this.boundBeforeStreamAction)
        }
    }

    // 設定全域函數（為了向後相容動態載入的內容）
    setupGlobalFunctions() {
        window.handleWeeklyClosureSubmit = (event) => {
            return this.submitWeeklyForm(event)
        }

        window.selectWeekdayInForm = (weekday) => {
            return this.selectWeekdayInForm(weekday)
        }

        window.checkExistingClosureDates = () => {
            checkExistingClosureDatesRetryCount = 0 // 重置重試計數
            return this.checkExistingClosureDates()
        }

        window.updateStatistics = () => {
            return this.updateStatistics()
        }
    }

    // 檢查已存在的公休設定
    checkExistingClosureDates() {
        const existingWeekdays = new Set()

        // 從頁面的公休日清單中提取已設定的週幾
        const closureDateItems = document.querySelectorAll('#closure_dates_list .border')

        closureDateItems.forEach((item, index) => {
            const titleElement = item.querySelector('h4')
            if (titleElement) {
                const titleText = titleElement.textContent.trim()

                if (titleText.includes('每週') && titleText.includes('公休')) {
                    const weekdayMatch = titleText.match(/每週\s*(週[一二三四五六日])\s*公休/)
                    if (weekdayMatch) {
                        const weekdayName = weekdayMatch[1]
                        const weekdayNumber = this.getWeekdayNumber(weekdayName)

                        if (weekdayNumber) {
                            existingWeekdays.add(weekdayNumber)
                        }
                    }
                }
            }
        })

        // 更新 checkbox 狀態
        this.updateWeekdayCheckboxes(existingWeekdays)
    }

    // 更新週幾 checkbox 狀態
    updateWeekdayCheckboxes(existingWeekdays) {
        const weekdayCheckboxes = this.weekdayCheckboxTargets

        weekdayCheckboxes.forEach((checkbox) => {
            const weekdayValue = parseInt(checkbox.value)
            const label = checkbox.closest('label')
            const textSpan = label ? label.querySelector('span:last-child') : null

            if (existingWeekdays.has(weekdayValue)) {
                // 已設定的週幾：禁用且顯示為已設定
                checkbox.checked = false
                checkbox.disabled = true

                if (label) {
                    label.classList.add('bg-red-50', 'border-red-200', 'cursor-not-allowed', 'opacity-60')
                    label.classList.remove('hover:bg-blue-100', 'border-gray-300')

                    if (textSpan) {
                        const weekdayNames = ['週日', '週一', '週二', '週三', '週四', '週五', '週六']
                        const originalText =
                            weekdayNames[weekdayValue] || textSpan.textContent.trim().replace(/\s*\(.*?\).*/, '')
                        textSpan.innerHTML = `${originalText} <br><span class="text-xs text-red-600 font-medium">(已設定)</span>`
                    }
                }
            } else {
                // 未設定的週幾：確保可以正常選擇
                checkbox.checked = false
                checkbox.disabled = false

                if (label) {
                    label.classList.remove('bg-red-50', 'border-red-200', 'cursor-not-allowed', 'opacity-60')
                    label.classList.add('hover:bg-blue-100', 'border-gray-300')

                    if (textSpan) {
                        const weekdayNames = ['週日', '週一', '週二', '週三', '週四', '週五', '週六']
                        textSpan.innerHTML =
                            weekdayNames[weekdayValue] || textSpan.textContent.replace(/\s*\(.*?\).*/, '').trim()
                    }
                }
            }
        })
    }

    // 提交每週公休表單
    async submitWeeklyForm(event) {
        event.preventDefault()

        try {
            // 檢查已勾選的項目
            const allCheckedBoxes = this.element.querySelectorAll('input[name="weekdays[]"]:checked')
            const enabledCheckedBoxes = this.element.querySelectorAll('input[name="weekdays[]"]:checked:not(:disabled)')

            // 檢查是否有嘗試選擇已設定的週幾
            const disabledCheckedBoxes = Array.from(allCheckedBoxes).filter((cb) => cb.disabled)
            if (disabledCheckedBoxes.length > 0) {
                const disabledWeekdays = disabledCheckedBoxes
                    .map((cb) => {
                        const weekdayNames = ['週日', '週一', '週二', '週三', '週四', '週五', '週六']
                        return weekdayNames[parseInt(cb.value)]
                    })
                    .join('、')

                alert(`無法選擇已設定的公休日：${disabledWeekdays}\n\n請取消勾選已設定的項目，只選擇尚未設定的週幾。`)

                // 自動取消勾選禁用的項目
                disabledCheckedBoxes.forEach((cb) => (cb.checked = false))
                return
            }

            if (enabledCheckedBoxes.length === 0) {
                alert('請至少選擇一個尚未設定的定休日')
                return
            }

            // 再次檢查重複
            const selectedWeekdays = Array.from(enabledCheckedBoxes).map((cb) => parseInt(cb.value))
            const existingWeekdays = this.getExistingWeekdays()
            const duplicates = selectedWeekdays.filter((weekday) => existingWeekdays.has(weekday))

            if (duplicates.length > 0) {
                const duplicateNames = duplicates
                    .map((weekday) => {
                        const weekdayNames = ['週日', '週一', '週二', '週三', '週四', '週五', '週六']
                        return weekdayNames[weekday]
                    })
                    .join('、')

                alert(`檢測到重複的公休設定：${duplicateNames}\n\n這些週幾已經設定過公休日，無法重複建立。`)
                return
            }

            // 獲取原因
            const reasonField = this.element.querySelector('input[name*="reason"]')
            const reason = reasonField ? reasonField.value : '每週固定公休'

            // 提交請求
            await this.submitWeeklyClosureRequests(enabledCheckedBoxes, reason)

            // 成功後處理
            alert('設定成功！')
            enabledCheckedBoxes.forEach((checkbox) => (checkbox.checked = false))

            // 重新載入頁面
            setTimeout(() => window.location.reload(), 500)
        } catch (error) {
            console.error('💥 設定失敗:', error)
            alert(`設定失敗：${error.message}`)
        }
    }

    // 提交每週公休請求
    async submitWeeklyClosureRequests(checkboxes, reason) {
        const csrfToken = this.getCSRFToken()

        const promises = Array.from(checkboxes).map(async (checkbox, index) => {
            const weekday = parseInt(checkbox.value)
            // 計算目標日期
            const targetDate = this.calculateTargetDate(weekday)

            // 準備表單資料
            const formData = new FormData()
            formData.append('closure_date[date]', targetDate)
            formData.append('closure_date[reason]', reason)
            formData.append('closure_date[closure_type]', 'regular')
            formData.append('closure_date[all_day]', 'true')
            formData.append('closure_date[recurring]', 'true')
            formData.append('closure_date[weekday]', weekday)

            // 發送請求
            const response = await fetch(this.closureDatesUrlValue, {
                method: 'POST',
                body: formData,
                headers: {
                    'X-CSRF-Token': csrfToken,
                    Accept: 'text/vnd.turbo-stream.html',
                    'X-Requested-With': 'XMLHttpRequest',
                },
            })

            if (!response.ok) {
                const errorText = await response.text()
                console.error(`❌ Request ${index + 1} failed:`, errorText)
                throw new Error(`HTTP ${response.status}: ${response.statusText}`)
            }

            return response
        })

        await Promise.all(promises)
    }

    // 點選右側公休項目來選擇對應週幾
    selectWeekdayInForm(weekday) {
        if (!weekday) {
            return
        }

        const checkbox = this.element.querySelector(`input[name="weekdays[]"][value="${weekday}"]`)
        if (checkbox && !checkbox.disabled) {
            checkbox.checked = !checkbox.checked

            // 視覺反饋
            const label = checkbox.closest('label')
            if (label) {
                label.classList.add('bg-blue-200', 'scale-105')
                setTimeout(() => {
                    label.classList.remove('bg-blue-200', 'scale-105')
                }, 300)
            }
        } else if (checkbox && checkbox.disabled) {
            alert('此週幾已經設定過公休日')
        }
    }

    // 更新統計數字
    updateStatistics() {
        const allItems = document.querySelectorAll('#closure_dates_list .border')
        const recurringCount = Array.from(document.querySelectorAll('#closure_dates_list h4')).filter((h4) =>
            h4.textContent.includes('每週')
        ).length
        const specialCount = Array.from(document.querySelectorAll('#closure_dates_list h4')).filter(
            (h4) => !h4.textContent.includes('每週')
        ).length
        const totalCount = allItems.length

        // 更新統計卡片
        const badges = {
            recurring: document.querySelector('.bg-blue-100.text-blue-800'),
            special: document.querySelector('.bg-yellow-100.text-yellow-800'),
            total: document.querySelector('.bg-gray-100.text-gray-800'),
        }

        if (badges.recurring) badges.recurring.textContent = `${recurringCount} 項`
        if (badges.special) badges.special.textContent = `${specialCount} 天`
        if (badges.total) badges.total.textContent = `${totalCount} 項`
    }

    // 輔助方法：獲取週幾數字（使用 0-6 格式）
    getWeekdayNumber(weekdayName) {
        const weekdayMap = {
            週日: 0,
            週一: 1,
            週二: 2,
            週三: 3,
            週四: 4,
            週五: 5,
            週六: 6,
        }
        return weekdayMap[weekdayName]
    }

    // 輔助方法：獲取已存在的週幾
    getExistingWeekdays() {
        const existingWeekdays = new Set()
        const closureDateItems = document.querySelectorAll('#closure_dates_list .border')

        closureDateItems.forEach((item) => {
            const titleElement = item.querySelector('h4')
            if (
                titleElement &&
                titleElement.textContent.includes('每週') &&
                titleElement.textContent.includes('公休')
            ) {
                const weekdayMatch = titleElement.textContent.match(/每週\s*(週[一二三四五六日])\s*公休/)
                if (weekdayMatch) {
                    const weekdayNumber = this.getWeekdayNumber(weekdayMatch[1])
                    if (weekdayNumber) {
                        existingWeekdays.add(weekdayNumber)
                    }
                }
            }
        })

        return existingWeekdays
    }

    // 輔助方法：計算目標日期（使用 0-6 格式）
    calculateTargetDate(weekday) {
        const today = new Date()
        const todayWeekday = today.getDay() // 0-6 格式（週日=0）
        let daysToAdd = weekday - todayWeekday
        if (daysToAdd <= 0) {
            daysToAdd += 7
        }
        const targetDate = new Date(today)
        targetDate.setDate(today.getDate() + daysToAdd)

        return targetDate.toISOString().split('T')[0]
    }

    // 輔助方法：獲取 CSRF Token
    getCSRFToken() {
        const token = document.querySelector('[name="csrf-token"]')?.content
        if (!token) {
            throw new Error('CSRF token not found')
        }
        return token
    }

    // 處理 Turbo Frame 載入
    handleTurboFrameLoad(event) {
        setTimeout(() => {
            this.checkExistingClosureDates()
        }, 100)
    }

    // 處理 Turbo Stream 動作前事件
    handleBeforeStreamAction(event) {
        if (
            event.detail.action === 'replace' &&
            (event.detail.target === 'weekly-closure-section' || event.detail.target === 'closure-dates-content')
        ) {
            // 在 Stream 動作完成後重新初始化
            setTimeout(() => {
                this.setupGlobalFunctions()
                this.checkExistingClosureDates()

                // 確保 flash 訊息自動隱藏功能正常工作
                const flashElements = document.querySelectorAll('[data-flash-message]')
                flashElements.forEach((flashElement) => {
                    const autoHideTime = flashElement.dataset.autoHide || 3000
                    setTimeout(() => {
                        flashElement.style.transition = 'opacity 0.5s ease-out'
                        flashElement.style.opacity = '0'
                        setTimeout(() => {
                            flashElement.remove()
                        }, 500)
                    }, parseInt(autoHideTime))
                })
            }, 300)
        }
    }
}

// 立即設定基本的全域函數防護（避免無限迴圈）
let checkExistingClosureDatesRetryCount = 0
const maxRetries = 3

window.checkExistingClosureDates =
    window.checkExistingClosureDates ||
    function () {
        if (checkExistingClosureDatesRetryCount >= maxRetries) {
            return
        }

        checkExistingClosureDatesRetryCount++
    }
