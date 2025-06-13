import { Controller } from '@hotwired/stimulus'
import flatpickr from 'flatpickr'

export default class extends Controller {
    static targets = [
        'adultSelect',
        'childSelect',
        'dateTimeSection',
        'loadingState',
        'calendarInput',
        'selectedDateDisplay',
        'selectedDateText',
        'selectedWeekdayText',
        'fullBookedState',
        'fullBookedUntilDate',
        'timeSlotsContainer',
        'afternoonSlots',
        'afternoonSlotsGrid',
        'eveningSlots',
        'eveningSlotsGrid',
        'nextStepButton',
        'phoneInput',
        'phoneLimitWarning',
    ]

    static values = {
        restaurantSlug: String,
    }

    connect() {
        console.log('ReservationCalendarController connected')
        this.selectedDate = null
        this.selectedTime = null
        this.availableDates = []
        this.businessPeriods = []
        this.flatpickrInstance = null

        // 初始載入
        this.updatePartySize()
    }

    disconnect() {
        // 清理 Flatpickr 實例
        if (this.flatpickrInstance) {
            this.flatpickrInstance.destroy()
        }
    }

    // 格式化日期為本地時區字串 (YYYY-MM-DD) - 使用與第一個檔案相同的方式
    formatDateToLocal(date) {
        // 使用本地時區格式化，避免時區轉換問題
        const year = date.getFullYear()
        const month = String(date.getMonth() + 1).padStart(2, '0')
        const day = String(date.getDate()).padStart(2, '0')
        return `${year}-${month}-${day}`
    }

    // 解析日期字串為本地日期物件 - 修正時區處理
    parseLocalDate(dateString) {
        // 使用與第一個檔案相同的安全解析方式
        if (dateString.includes('T')) {
            dateString = dateString.split('T')[0]
        }
        const [year, month, day] = dateString.split('-').map(Number)
        return new Date(year, month - 1, day) // 月份需要減1
    }

    // 獲取本地化的週幾名稱
    getLocalWeekdayName(date) {
        const weekdays = ['日', '一', '二', '三', '四', '五', '六']
        return weekdays[date.getDay()]
    }

    // 檢查日期是否是今天或之前
    isDateBeforeOrToday(date) {
        const today = new Date()
        today.setHours(0, 0, 0, 0) // 設為今天的開始時間

        const checkDate = new Date(date)
        checkDate.setHours(0, 0, 0, 0) // 設為檢查日期的開始時間

        return checkDate <= today
    }

    // 當大人或小孩人數改變時
    updatePartySize() {
        const adults = parseInt(this.adultSelectTarget.value)
        const children = parseInt(this.childSelectTarget.value)
        const totalPartySize = adults + children

        // 檢查總人數限制
        if (totalPartySize > 12) {
            this.showError('總人數不能超過12人')
            return
        }

        this.partySize = totalPartySize
        this.loadAvailableDates()
    }

    // 載入可預約日期
    async loadAvailableDates() {
        try {
            this.showLoading()

            const response = await fetch(
                `/restaurant/${this.restaurantSlugValue}/available_dates?party_size=${this.partySize}`
            )

            if (!response.ok) {
                const errorData = await response.json()
                if (response.status === 503 && errorData.disabled) {
                    this.showError('線上訂位功能暫停服務，如需訂位請直接致電餐廳')
                    return
                }
                throw new Error('載入失敗')
            }

            const data = await response.json()
            this.availableDates = data.available_dates || []
            this.businessPeriods = data.business_periods || []

            // 過濾掉今天及之前的日期
            this.availableDates = this.availableDates.filter((dateStr) => {
                const date = this.parseLocalDate(dateStr)
                return !this.isDateBeforeOrToday(date)
            })

            console.log('載入的可用日期 (過濾後):', this.availableDates)

            if (this.availableDates.length === 0) {
                this.showFullBookedState(data.full_booked_until)
            } else {
                this.showCalendar()
                this.initializeFlatpickr()
            }
        } catch (error) {
            console.error('載入可預約日期失敗:', error)
            this.showError('載入失敗，請稍後再試')
        }
    }

    // 初始化 Flatpickr 日曆 - 修正日期處理方式
    initializeFlatpickr() {
        // 銷毀現有實例
        if (this.flatpickrInstance) {
            this.flatpickrInstance.destroy()
        }

        // 使用與第一個檔案相同的安全日期轉換方式
        const enabledDates = this.availableDates.map((dateStr) => {
            // 確保使用正確的日期解析，避免時區問題
            const [year, month, day] = dateStr.split('-').map(Number)
            return new Date(year, month - 1, day) // 月份需要減1
        })

        console.log('原始可用日期:', this.availableDates)
        console.log('轉換後的 Date 物件:', enabledDates)

        // 驗證轉換是否正確
        enabledDates.forEach((date, index) => {
            const originalStr = this.availableDates[index]
            const convertedStr = this.formatDateToLocal(date)
            const dayOfWeek = date.getDay()
            const weekdayNames = ['日', '一', '二', '三', '四', '五', '六']
            console.log(`${originalStr} -> ${convertedStr} (星期${weekdayNames[dayOfWeek]})`)
        })

        // 清空容器內容並設定基本樣式
        this.calendarInputTarget.innerHTML = ''
        this.calendarInputTarget.style.width = '100%'
        this.calendarInputTarget.style.maxWidth = '400px'
        this.calendarInputTarget.style.margin = '0 auto'

        // 設定繁體中文語言包
        const chineseTraditional = {
            weekdays: {
                // 確保星期順序正確：星期日開始
                shorthand: ['日', '一', '二', '三', '四', '五', '六'],
                longhand: ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'],
            },
            months: {
                shorthand: ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'],
                longhand: [
                    '一月',
                    '二月',
                    '三月',
                    '四月',
                    '五月',
                    '六月',
                    '七月',
                    '八月',
                    '九月',
                    '十月',
                    '十一月',
                    '十二月',
                ],
            },
            firstDayOfWeek: 0, // 星期日開始
            rangeSeparator: ' 到 ',
            weekAbbreviation: '週',
            scrollTitle: '滾動切換',
            toggleTitle: '點擊切換 12/24 小時制',
        }

        // 獲取明天的日期作為最小可選日期
        const tomorrow = new Date()
        tomorrow.setDate(tomorrow.getDate() + 1)
        tomorrow.setHours(0, 0, 0, 0)

        this.flatpickrInstance = flatpickr(this.calendarInputTarget, {
            locale: chineseTraditional,
            dateFormat: 'Y-m-d',
            minDate: tomorrow, // 設定最小日期為明天
            maxDate: new Date().fp_incr(60), // 60天後
            enable: enabledDates.length > 0 ? enabledDates : [], // 使用修正後的日期陣列
            disableMobile: true,
            inline: true, // 直接顯示日曆，不需要 input

            // 自定義日期禁用邏輯
            disable: [
                // 禁用今天及之前的所有日期
                {
                    from: new Date(1900, 0, 1), // 從很久以前開始
                    to: new Date(), // 到今天為止
                },
            ],

            onChange: (selectedDates) => {
                if (selectedDates.length > 0) {
                    const selectedDate = selectedDates[0]

                    // 雙重檢查：確保選擇的日期不是今天或之前
                    if (this.isDateBeforeOrToday(selectedDate)) {
                        this.showError('不可預定當天或過去的日期')
                        this.flatpickrInstance.clear()
                        return
                    }

                    this.selectDate(selectedDate)
                }
            },

            onReady: () => {
                // 日曆準備好後隱藏載入狀態
                this.hideLoading()
                console.log('Flatpickr ready - calendar initialized successfully')

                // 添加自定義樣式讓禁用的日期更明顯
                this.addDisabledDateStyles()
            },

            onDayCreate: (dObj, dStr, fp, dayElem) => {
                const date = dayElem.dateObj

                // 如果是今天或之前的日期，添加特殊樣式和提示
                if (this.isDateBeforeOrToday(date)) {
                    dayElem.classList.add('disabled-date')
                    dayElem.title = '不可預定當天或過去的日期'
                    dayElem.style.opacity = '0.3'
                    dayElem.style.cursor = 'not-allowed'
                    dayElem.style.textDecoration = 'line-through'
                }
            },
        })
    }

    // 添加禁用日期的自定義樣式
    addDisabledDateStyles() {
        const style = document.createElement('style')
        style.textContent = `
            .flatpickr-calendar .disabled-date {
                opacity: 0.3 !important;
                cursor: not-allowed !important;
                text-decoration: line-through !important;
                background-color: #f3f4f6 !important;
                color: #9ca3af !important;
            }
            
            .flatpickr-calendar .disabled-date:hover {
                background-color: #f3f4f6 !important;
                color: #9ca3af !important;
            }
            
            .flatpickr-calendar .flatpickr-disabled {
                opacity: 0.3 !important;
                cursor: not-allowed !important;
            }
        `

        if (!document.querySelector('#flatpickr-disabled-styles')) {
            style.id = 'flatpickr-disabled-styles'
            document.head.appendChild(style)
        }
    }

    // 顯示載入狀態
    showLoading() {
        this.loadingStateTarget.classList.remove('hidden')
        this.calendarInputTarget.style.display = 'none'
        this.fullBookedStateTarget.classList.add('hidden')
    }

    // 隱藏載入狀態
    hideLoading() {
        this.loadingStateTarget.classList.add('hidden')
    }

    // 顯示日曆
    showCalendar() {
        this.loadingStateTarget.classList.add('hidden')
        this.calendarInputTarget.style.display = 'block'
        this.fullBookedStateTarget.classList.add('hidden')
    }

    // 顯示完全預約滿的狀態
    showFullBookedState(fullBookedUntil) {
        this.loadingStateTarget.classList.add('hidden')
        this.calendarInputTarget.style.display = 'none'
        this.fullBookedStateTarget.classList.remove('hidden')

        if (fullBookedUntil && this.hasFullBookedUntilDateTarget) {
            const date = this.parseLocalDate(fullBookedUntil)
            const formattedDate = `${date.getMonth() + 1}月${date.getDate()}日`
            this.fullBookedUntilDateTarget.textContent = formattedDate
        }
    }

    // 選擇日期
    selectDate(date) {
        // 再次檢查是否為今天或之前的日期
        if (this.isDateBeforeOrToday(date)) {
            this.showError('不可預定當天或過去的日期')
            return
        }

        console.log('選擇日期:', date)
        this.selectedDate = date
        this.updateSelectedDateDisplay()
        this.loadAvailableTimeSlots()

        // 顯示日期時間選擇區域
        this.dateTimeSectionTarget.classList.remove('hidden')
    }

    // 更新選擇的日期顯示
    updateSelectedDateDisplay() {
        if (!this.selectedDate) return

        const month = this.selectedDate.getMonth() + 1
        const day = this.selectedDate.getDate()
        const weekday = this.getLocalWeekdayName(this.selectedDate)

        if (this.hasSelectedDateTextTarget) {
            this.selectedDateTextTarget.textContent = `${month}月${day}日`
        }

        if (this.hasSelectedWeekdayTextTarget) {
            this.selectedWeekdayTextTarget.textContent = `星期${weekday}`
        }

        if (this.hasSelectedDateDisplayTarget) {
            this.selectedDateDisplayTarget.textContent = `${month}月${day}日 星期${weekday}`
        }
    }

    // 載入可用時段
    async loadAvailableTimeSlots() {
        if (!this.selectedDate) return

        try {
            const dateString = this.formatDateToLocal(this.selectedDate)
            const response = await fetch(
                `/restaurant/${this.restaurantSlugValue}/available_times?date=${dateString}&party_size=${this.partySize}`
            )

            if (!response.ok) {
                const errorData = await response.json()
                if (response.status === 503 && errorData.disabled) {
                    this.showError('線上訂位功能暫停服務')
                    return
                }
                if (response.status === 422) {
                    this.showError(errorData.error || '無法取得可用時段')
                    return
                }
                throw new Error('載入時段失敗')
            }

            const data = await response.json()
            this.renderTimeSlots(data.available_times || [])
        } catch (error) {
            console.error('載入可用時段失敗:', error)
            this.showError('載入時段失敗，請稍後再試')
        }
    }

    // 渲染時段按鈕
    renderTimeSlots(timeSlots) {
        console.log('渲染時段:', timeSlots)

        // 清空現有時段
        if (this.hasAfternoonSlotsGridTarget) this.afternoonSlotsGridTarget.innerHTML = ''
        if (this.hasEveningSlotsGridTarget) this.eveningSlotsGridTarget.innerHTML = ''

        let hasAfternoon = false
        let hasEvening = false

        timeSlots.forEach((slot) => {
            const button = this.createTimeSlotButton(slot)
            const hour = parseInt(slot.time.split(':')[0])

            if (hour < 17) {
                // 下午時段 (17:00 之前)
                if (this.hasAfternoonSlotsGridTarget) {
                    this.afternoonSlotsGridTarget.appendChild(button)
                    hasAfternoon = true
                }
            } else {
                // 晚餐時段 (17:00 及之後)
                if (this.hasEveningSlotsGridTarget) {
                    this.eveningSlotsGridTarget.appendChild(button)
                    hasEvening = true
                }
            }
        })

        // 顯示/隱藏時段區塊
        if (this.hasAfternoonSlotsTarget) {
            this.afternoonSlotsTarget.style.display = hasAfternoon ? 'block' : 'none'
        }
        if (this.hasEveningSlotsTarget) {
            this.eveningSlotsTarget.style.display = hasEvening ? 'block' : 'none'
        }

        // 顯示時段容器
        if (this.hasTimeSlotsContainerTarget) {
            this.timeSlotsContainerTarget.classList.remove('hidden')
        }
    }

    // 創建時段按鈕
    createTimeSlotButton(slot) {
        const button = document.createElement('button')
        button.type = 'button'
        button.textContent = slot.time
        button.className =
            'px-4 py-2 border border-gray-300 rounded-lg text-sm hover:border-blue-500 hover:bg-blue-50 transition-colors'
        button.dataset.time = slot.time
        button.dataset.action = 'click->reservation-calendar#selectTimeSlot'
        button.dataset.slot = JSON.stringify(slot)

        return button
    }

    // 選擇時段
    selectTimeSlot(event) {
        const button = event.target
        const slot = JSON.parse(button.dataset.slot)

        this.selectedTime = slot
        console.log('選擇時段:', slot)

        this.updateTimeSlotButtons()

        // 啟用下一步按鈕
        if (this.hasNextStepButtonTarget) {
            this.nextStepButtonTarget.disabled = false
        }
    }

    // 更新時段按鈕狀態
    updateTimeSlotButtons() {
        const allButtons = [
            ...(this.hasAfternoonSlotsGridTarget ? this.afternoonSlotsGridTarget.querySelectorAll('button') : []),
            ...(this.hasEveningSlotsGridTarget ? this.eveningSlotsGridTarget.querySelectorAll('button') : []),
        ]

        allButtons.forEach((button) => {
            if (this.selectedTime && button.dataset.time === this.selectedTime.time) {
                button.className =
                    'px-4 py-2 border-2 border-blue-500 bg-blue-500 text-white rounded-lg text-sm transition-colors'
            } else {
                button.className =
                    'px-4 py-2 border border-gray-300 rounded-lg text-sm hover:border-blue-500 hover:bg-blue-50 transition-colors'
            }
        })
    }

    // 清除選擇的日期
    clearSelectedDate() {
        this.selectedDate = null
        this.selectedTime = null

        // 隱藏日期時間選擇區域
        if (this.hasDateTimeSectionTarget) {
            this.dateTimeSectionTarget.classList.add('hidden')
        }

        // 清除 Flatpickr 選擇
        if (this.flatpickrInstance) {
            this.flatpickrInstance.clear()
        }

        // 禁用下一步按鈕
        if (this.hasNextStepButtonTarget) {
            this.nextStepButtonTarget.disabled = true
        }
    }

    // 進入下一步（填寫訂位資訊）
    proceedToReservation() {
        if (!this.selectedDate || !this.selectedTime) {
            this.showError('請選擇日期和時段')
            return
        }

        // 最後一次檢查日期是否有效
        if (this.isDateBeforeOrToday(this.selectedDate)) {
            this.showError('不可預定當天或過去的日期')
            this.clearSelectedDate()
            return
        }

        const dateString = this.formatDateToLocal(this.selectedDate)
        const params = new URLSearchParams({
            date: dateString,
            time: this.selectedTime.time,
            party_size: this.partySize,
        })

        window.location.href = `/restaurant/${this.restaurantSlugValue}/reservations/new?${params}`
    }

    // 顯示錯誤訊息
    showError(message) {
        // 創建或更新錯誤訊息元素
        let errorElement = document.querySelector('#reservation-error-message')
        if (!errorElement) {
            errorElement = document.createElement('div')
            errorElement.id = 'reservation-error-message'
            errorElement.className = 'bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4'
            this.element.insertBefore(errorElement, this.element.firstChild)
        }

        errorElement.textContent = message
        errorElement.style.display = 'block'

        // 3秒後自動隱藏
        setTimeout(() => {
            if (errorElement) {
                errorElement.style.display = 'none'
            }
        }, 3000)
    }
}
