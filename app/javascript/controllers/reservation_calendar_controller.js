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
                throw new Error('載入失敗')
            }

            const data = await response.json()
            this.availableDates = data.available_dates || []
            this.businessPeriods = data.business_periods || []

            console.log('載入的可用日期:', this.availableDates)

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

        // 設定繁體中文語言包 - 使用與第一個檔案完全相同的設定
        // const chineseTraditional = {
        //     weekdays: {
        //         // 確保星期順序正確：星期日開始
        //         shorthand: ['日', '一', '二', '三', '四', '五', '六'],
        //         longhand: ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'],
        //     },
        //     months: {
        //         shorthand: ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'],
        //         longhand: [
        //             '一月',
        //             '二月',
        //             '三月',
        //             '四月',
        //             '五月',
        //             '六月',
        //             '七月',
        //             '八月',
        //             '九月',
        //             '十月',
        //             '十一月',
        //             '十二月',
        //         ],
        //     },
        //     firstDayOfWeek: 0, // 星期日開始
        //     rangeSeparator: ' 到 ',
        //     weekAbbreviation: '週',
        //     scrollTitle: '滾動切換',
        //     toggleTitle: '點擊切換 12/24 小時制',
        // }

        this.flatpickrInstance = flatpickr(this.calendarInputTarget, {
            locale: chineseTraditional,
            dateFormat: 'Y-m-d',
            minDate: 'today',
            maxDate: new Date().fp_incr(60), // 60天後
            enable: enabledDates, // 使用修正後的日期陣列
            disableMobile: true,
            inline: true, // 直接顯示日曆，不需要 input
            onChange: (selectedDates) => {
                if (selectedDates.length > 0) {
                    this.selectDate(selectedDates[0])
                }
            },
            onReady: () => {
                // 日曆準備好後隱藏載入狀態
                this.hideLoading()

                console.log('Flatpickr ready - calendar initialized successfully')

                // 檢查日曆結構和日期對應
                setTimeout(() => {
                    const calendarElement = this.calendarInputTarget.querySelector('.flatpickr-calendar')
                    if (calendarElement) {
                        const weekdayHeaders = calendarElement.querySelectorAll('.flatpickr-weekday')
                        console.log(
                            'Weekday headers:',
                            Array.from(weekdayHeaders).map((el) => el.textContent)
                        )

                        // 檢查可用日期在日曆上的顯示
                        enabledDates.slice(0, 3).forEach((date) => {
                            const dateStr = this.formatDateToLocal(date)
                            const dayOfWeek = date.getDay()
                            const weekdayNames = ['日', '一', '二', '三', '四', '五', '六']
                            console.log(`檢查: ${dateStr} 應該是星期${weekdayNames[dayOfWeek]}`)
                        })
                    }
                }, 100)
            },
        })
    }

    // 顯示載入狀態
    showLoading() {
        this.loadingStateTarget.classList.remove('hidden')
        this.calendarInputTarget.style.display = 'none'
        this.fullBookedStateTarget.classList.add('hidden')
        this.timeSlotsContainerTarget.classList.add('hidden')
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

    // 顯示客滿狀態
    showFullBookedState(fullBookedUntil) {
        this.loadingStateTarget.classList.add('hidden')
        this.calendarInputTarget.style.display = 'none'
        this.fullBookedStateTarget.classList.remove('hidden')
        this.timeSlotsContainerTarget.classList.add('hidden')

        if (fullBookedUntil) {
            // 使用修正後的本地日期解析
            const date = this.parseLocalDate(fullBookedUntil.split('T')[0])
            const formattedDate = `${date.getMonth() + 1}月${date.getDate()}日`
            this.fullBookedUntilDateTarget.textContent = formattedDate
        }
    }

    // 選擇日期 - 修正日期處理方式
    selectDate(date) {
        // 使用與第一個檔案相同的安全處理方式
        const year = date.getFullYear()
        const month = date.getMonth()
        const day = date.getDate()

        // 建立本地時區的日期物件
        this.selectedDate = new Date(year, month, day, 0, 0, 0)
        this.selectedTime = null

        console.log('選擇的日期:', this.selectedDate, '格式化為:', this.formatDateToLocal(this.selectedDate))

        // 更新選中日期顯示
        this.updateSelectedDateDisplay()

        // 載入該日期的可用時段
        this.loadAvailableTimeSlots()
    }

    // 更新選中日期顯示
    updateSelectedDateDisplay() {
        if (!this.selectedDate) {
            this.selectedDateDisplayTarget.classList.add('hidden')
            return
        }

        // 使用本地時區的日期，避免時區偏移問題
        const month = this.selectedDate.getMonth() + 1
        const day = this.selectedDate.getDate()
        const year = this.selectedDate.getFullYear()
        const weekday = this.getLocalWeekdayName(this.selectedDate)

        this.selectedDateTextTarget.textContent = `${month}月${day}日`
        this.selectedWeekdayTextTarget.textContent = `週${weekday}`
        this.selectedDateDisplayTarget.classList.remove('hidden')

        console.log(`更新顯示: ${month}月${day}日 週${weekday}`)
    }

    // 載入可用時段
    async loadAvailableTimeSlots() {
        try {
            // 使用本地時區格式化日期字串
            const dateString = this.formatDateToLocal(this.selectedDate)

            const response = await fetch(
                `/restaurant/${this.restaurantSlugValue}/available_times?date=${dateString}&party_size=${this.partySize}`
            )

            if (!response.ok) {
                throw new Error('載入時段失敗')
            }

            const data = await response.json()
            this.renderTimeSlots(data.time_slots || [])
            this.timeSlotsContainerTarget.classList.remove('hidden')
        } catch (error) {
            console.error('載入時段失敗:', error)
            this.showError('載入時段失敗，請稍後再試')
        }
    }

    // 渲染時段
    renderTimeSlots(timeSlots) {
        // 清空現有時段
        this.afternoonSlotsGridTarget.innerHTML = ''
        this.eveningSlotsGridTarget.innerHTML = ''

        // 分類時段
        const afternoonSlots = timeSlots.filter((slot) => {
            const hour = parseInt(slot.time.split(':')[0])
            return hour >= 11 && hour < 17
        })

        const eveningSlots = timeSlots.filter((slot) => {
            const hour = parseInt(slot.time.split(':')[0])
            return hour >= 17
        })

        // 渲染下午時段
        if (afternoonSlots.length > 0) {
            afternoonSlots.forEach((slot) => {
                const button = this.createTimeSlotButton(slot)
                this.afternoonSlotsGridTarget.appendChild(button)
            })
            this.afternoonSlotsTarget.classList.remove('hidden')
        } else {
            this.afternoonSlotsTarget.classList.add('hidden')
        }

        // 渲染晚上時段
        if (eveningSlots.length > 0) {
            eveningSlots.forEach((slot) => {
                const button = this.createTimeSlotButton(slot)
                this.eveningSlotsGridTarget.appendChild(button)
            })
            this.eveningSlotsTarget.classList.remove('hidden')
        } else {
            this.eveningSlotsTarget.classList.add('hidden')
        }
    }

    // 建立時段按鈕
    createTimeSlotButton(slot) {
        const button = document.createElement('button')
        button.type = 'button'
        button.className = 'time-slot-button'
        button.textContent = slot.time

        if (slot.available) {
            button.addEventListener('click', () => this.selectTimeSlot(slot))
        } else {
            button.disabled = true
        }

        return button
    }

    // 選擇時段
    selectTimeSlot(slot) {
        this.selectedTime = slot

        // 更新所有時段按鈕的狀態
        this.updateTimeSlotButtons()

        // 啟用下一步按鈕
        this.nextStepButtonTarget.disabled = false
        this.nextStepButtonTarget.className =
            'w-full bg-blue-600 text-white py-3 px-6 rounded-lg font-medium hover:bg-blue-700 cursor-pointer transition-colors duration-200'
    }

    // 更新時段按鈕狀態
    updateTimeSlotButtons() {
        const allButtons = [
            ...this.afternoonSlotsGridTarget.querySelectorAll('button'),
            ...this.eveningSlotsGridTarget.querySelectorAll('button'),
        ]

        allButtons.forEach((button) => {
            if (this.selectedTime && button.textContent === this.selectedTime.time) {
                button.className = 'time-slot-button selected'
            } else {
                button.className = 'time-slot-button'
                if (button.disabled) {
                    button.className += ' disabled'
                }
            }
        })
    }

    // 清除選中日期
    clearSelectedDate() {
        this.selectedDate = null
        this.selectedTime = null
        this.selectedDateDisplayTarget.classList.add('hidden')
        this.timeSlotsContainerTarget.classList.add('hidden')

        // 清除 Flatpickr 選擇
        if (this.flatpickrInstance) {
            this.flatpickrInstance.clear()
        }

        // 禁用下一步按鈕
        this.nextStepButtonTarget.disabled = true
        this.nextStepButtonTarget.className =
            'w-full bg-gray-300 text-gray-500 py-3 px-6 rounded-lg font-medium cursor-not-allowed'
    }

    // 進入訂位流程
    proceedToReservation() {
        if (!this.selectedDate || !this.selectedTime) {
            this.showError('請選擇日期和時間')
            return
        }

        const params = new URLSearchParams({
            party_size: this.partySize,
            adults: this.adultSelectTarget.value,
            children: this.childSelectTarget.value,
            date: this.formatDateToLocal(this.selectedDate),
            time: this.selectedTime.time,
            business_period_id: this.selectedTime.business_period_id,
        })

        window.location.href = `/restaurant/${this.restaurantSlugValue}/reservations/new?${params.toString()}`
    }

    // 顯示錯誤訊息
    showError(message) {
        // 這裡可以實作錯誤訊息顯示
        alert(message)
    }
}
