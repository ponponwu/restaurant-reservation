import { Controller } from '@hotwired/stimulus'
import flatpickr from 'flatpickr'
import zhTw from 'flatpickr/dist/l10n/zh-tw.js'
import 'flatpickr/dist/themes/dark.css'

export default class extends Controller {
    static targets = ['date', 'calendar', 'timeSlots', 'periodInfo', 'nextStep', 'adultCount', 'childCount']
    static values = {
        restaurantSlug: String,
        businessHours: Object,
        maxPartySize: Number,
        minPartySize: Number,
    }

    connect() {
        if (process.env.NODE_ENV === 'development') {
            console.log('🔥 Reservation controller connected')
            console.log('🔥 Controller targets:', this.targets)
            console.log('🔥 timeSlots target available:', this.hasTimeSlotsTarget)
            console.log('🔥 dateTarget available:', this.hasDateTarget)
            console.log('🔥 Restaurant slug:', this.restaurantSlugValue)
            console.log('🔥 Max party size:', this.maxPartySizeValue)
            console.log('🔥 Min party size:', this.minPartySizeValue)
        }

        this.selectedDate = null
        this.selectedPeriodId = null
        this.selectedTime = null
        this.maxReservationDays = 30 // 預設值，將從 API 獲取實際值

        // 延遲初始化，確保 DOM 完全載入
        setTimeout(() => {
            this.initDatePicker()
            this.setupGuestCountListeners()
            this.updateGuestCountOptions() // 初始化人數選項
        }, 100)
    }

    setupGuestCountListeners() {
        const handleGuestCountChange = () => {
            console.log('🔥 Guest count changed, updating form...')

            // 動態更新選項
            this.updateGuestCountOptions()

            this.updateHiddenFields()

            // 清除當前選中的時段，因為人數變更可能會影響可用性
            this.clearSelectedTimeSlot()

            // 重新獲取可用日期（因為人數變更可能影響日期可用性）
            if (this.datePicker) {
                this.refreshAvailableDates()
            } else {
                this.initDatePicker()
            }

            // 如果已經選了日期，重新載入該日期的時段
            if (this.selectedDate) {
                console.log('🔥 Reloading time slots for selected date:', this.selectedDate)
                this.loadAllTimeSlots(this.selectedDate)
            }
        }

        if (this.hasAdultCountTarget) {
            this.adultCountTarget.addEventListener('change', handleGuestCountChange)
        }

        if (this.hasChildCountTarget) {
            this.childCountTarget.addEventListener('change', handleGuestCountChange)
        }

        // 初始化隱藏欄位
        this.updateHiddenFields()
    }

    updateGuestCountOptions() {
        if (!this.hasAdultCountTarget || !this.hasChildCountTarget) return

        const currentAdults = parseInt(this.adultCountTarget.value) || 1
        const currentChildren = parseInt(this.childCountTarget.value) || 0
        const maxPartySize = this.maxPartySizeValue || 6
        const minPartySize = this.minPartySizeValue || 1

        console.log('🔥 Updating guest count options:', { currentAdults, currentChildren, maxPartySize, minPartySize })

        // 更新大人選項 (至少1人)
        this.updateSelectOptions(this.adultCountTarget, currentAdults, 1, maxPartySize - currentChildren)

        // 更新小孩選項 (可以是0人)
        this.updateSelectOptions(this.childCountTarget, currentChildren, 0, maxPartySize - currentAdults)

        // 驗證當前選擇是否合法
        this.validateCurrentSelection()
    }

    updateSelectOptions(selectElement, currentValue, minValue, maxValue) {
        // 清空現有選項
        selectElement.innerHTML = ''

        // 生成新選項
        for (let i = minValue; i <= maxValue; i++) {
            const option = document.createElement('option')
            option.value = i
            option.textContent = i
            if (i === currentValue) {
                option.selected = true
            }
            selectElement.appendChild(option)
        }

        console.log(`🔥 Updated ${selectElement.name} options: ${minValue}-${maxValue}, current: ${currentValue}`)
    }

    validateCurrentSelection() {
        const adults = parseInt(this.adultCountTarget.value) || 1
        const children = parseInt(this.childCountTarget.value) || 0
        const totalPartySize = adults + children
        const maxPartySize = this.maxPartySizeValue || 6

        console.log('🔥 Validating selection:', { adults, children, totalPartySize, maxPartySize })

        // 如果總人數超過上限，調整小孩數
        if (totalPartySize > maxPartySize) {
            const adjustedChildren = Math.max(0, maxPartySize - adults)
            console.log('🔥 Adjusting children count from', children, 'to', adjustedChildren)
            this.childCountTarget.value = adjustedChildren

            // 重新更新選項以反映新的狀態
            setTimeout(() => this.updateGuestCountOptions(), 10)
        }

        // 如果大人數為0，調整為1
        if (adults < 1) {
            console.log('🔥 Adjusting adults count to minimum 1')
            this.adultCountTarget.value = 1
            setTimeout(() => this.updateGuestCountOptions(), 10)
        }
    }

    updateHiddenFields() {
        const adultHiddenField = document.getElementById('adult_count')
        const childHiddenField = document.getElementById('child_count')

        if (adultHiddenField && this.hasAdultCountTarget) {
            adultHiddenField.value = this.adultCountTarget.value
        }

        if (childHiddenField && this.hasChildCountTarget) {
            childHiddenField.value = this.childCountTarget.value
        }
    }

    getCurrentPartySize() {
        const adults = this.hasAdultCountTarget ? parseInt(this.adultCountTarget.value) || 0 : 2
        const children = this.hasChildCountTarget ? parseInt(this.childCountTarget.value) || 0 : 0
        return adults + children
    }

    async initDatePicker() {
        console.log('🔥 Starting initDatePicker...')

        if (!this.hasCalendarTarget) {
            console.error('🔥 No calendar target found!')
            return
        }

        // 銷毀現有的 flatpickr 實例
        if (this.datePicker) {
            this.datePicker.destroy()
            this.datePicker = null
        }

        try {
            // 取得可預約日資訊
            const partySize = this.getCurrentPartySize()
            const apiUrl = `/restaurants/${this.restaurantSlugValue}/available_days?party_size=${partySize}`
            console.log('🔥 Fetching from:', apiUrl)

            const response = await fetch(apiUrl, {
                headers: {
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                },
            })
            console.log('🔥 API response status:', response.status)

            if (response.status === 503) {
                const errorData = await response.json()
                this.showServiceUnavailable(errorData.message || errorData.error)
                return
            }

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`)
            }

            const data = await response.json()
            console.log('🔥 Available days data:', data)

            // 更新額滿提示訊息
            this.updateFullBookingNotice(data)

            // 計算不可用日期 - 使用新的 API 回應格式
            const disabledDates = this.calculateDisabledDates(
                data.weekly_closures || [],
                data.special_closures || [],
                data.has_capacity
            )

            console.log('🔥 Disabled dates:', disabledDates)

            // 初始化 flatpickr
            this.datePicker = flatpickr(this.calendarTarget, {
                inline: true,
                locale: zhTw.zh_tw,
                dateFormat: 'Y-m-d',
                minDate: 'today',
                maxDate: new Date().fp_incr(this.maxReservationDays),
                disable: disabledDates,
                onChange: (selectedDates, dateStr) => {
                    console.log('🔥 Date selected:', dateStr)
                    this.selectedDate = dateStr

                    // 更新兩個日期欄位
                    if (this.hasDateTarget) {
                        this.dateTarget.value = dateStr
                    }

                    // 更新表單提交用的日期欄位
                    const reservationDateField = document.getElementById('reservation_date')
                    if (reservationDateField) {
                        reservationDateField.value = dateStr
                    }

                    // 更新 URL，移除 show_all 參數並設定 date_filter
                    this.updateUrlWithDate(dateStr)

                    this.loadAllTimeSlots(dateStr)
                },
                onReady: () => {
                    this.styleFlatpickr()
                },
            })
        } catch (error) {
            console.error('🔥 Error initializing date picker:', error)
            this.showError('載入日期選擇器時發生錯誤')
        }
    }

    styleFlatpickr() {
        const calendarElement = this.calendarTarget.querySelector('.flatpickr-calendar')
        if (calendarElement) {
            // 確保日曆是 inline 模式且占滿容器
            calendarElement.classList.add('inline')

            // 移除預設的定位樣式，讓 CSS 樣式生效
            calendarElement.style.position = 'relative'
            calendarElement.style.top = 'auto'
            calendarElement.style.left = 'auto'
            calendarElement.style.display = 'block'
            calendarElement.style.width = '100%'
            calendarElement.style.maxWidth = 'none'

            // 確保日期容器占滿寬度
            const dayContainer = calendarElement.querySelector('.dayContainer')
            if (dayContainer) {
                dayContainer.style.width = '100%'
                dayContainer.style.minWidth = '100%'
                dayContainer.style.maxWidth = '100%'
            }

            // 確保 days 容器占滿寬度
            const daysContainer = calendarElement.querySelector('.flatpickr-days')
            if (daysContainer) {
                daysContainer.style.width = '100%'
            }
        }
    }

    updateFullBookingNotice(data) {
        // 簡化邏輯：不顯示額滿提示訊息
        if (this.hasFullBookingNoticeTarget) {
            this.fullBookingNoticeTarget.classList.add('hidden')
        }
    }

    async loadAllTimeSlots(date) {
        console.log('🔥 Loading time slots for date:', date)

        if (!this.hasTimeSlotsTarget) {
            console.error('🔥 No timeSlots target found!')
            return
        }

        try {
            const partySize = this.getCurrentPartySize()
            const adults = this.hasAdultCountTarget ? parseInt(this.adultCountTarget.value) || 0 : partySize
            const children = this.hasChildCountTarget ? parseInt(this.childCountTarget.value) || 0 : 0

            const url = `/restaurants/${this.restaurantSlugValue}/reservations/available_slots?date=${date}&adult_count=${adults}&child_count=${children}`
            console.log('🔥 Fetching time slots from:', url)

            const response = await fetch(url, {
                headers: {
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                },
            })
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`)
            }

            const data = await response.json()
            console.log('🔥 Time slots data:', data)

            this.renderTimeSlots(data.slots || [])
            this.updateFormState()
        } catch (error) {
            console.error('🔥 Error loading time slots:', error)
            this.showError('載入時間時發生錯誤')
        }
    }

    renderTimeSlots(timeSlots) {
        this.timeSlotsTarget.innerHTML = ''

        if (timeSlots.length === 0) {
            this.timeSlotsTarget.innerHTML = '<p class="text-gray-500 text-center py-4">此日期無可用時間</p>'
            return
        }

        // 按餐期分組時間槽
        const groupedSlots = this.groupTimeSlotsByPeriod(timeSlots)

        Object.entries(groupedSlots).forEach(([periodName, slots]) => {
            const periodDiv = document.createElement('div')
            periodDiv.className = 'mb-6'

            const periodTitle = document.createElement('h3')
            periodTitle.className = 'text-white font-medium mb-3 flex items-center'
            periodTitle.innerHTML = `
                <span class="w-2 h-2 bg-green-500 rounded-full mr-2"></span>
                ${periodName}
            `
            periodDiv.appendChild(periodTitle)

            const slotsGrid = document.createElement('div')
            slotsGrid.className = 'grid grid-cols-2 gap-3'

            slots.forEach((slot) => {
                const button = document.createElement('button')
                button.type = 'button'
                button.className = `
                    bg-gray-800 border border-gray-600 rounded-lg px-4 py-3 text-white text-center
                    hover:bg-gray-700 hover:border-gray-500 transition-colors
                    focus:outline-none focus:ring-2 focus:ring-blue-500
                    ${slot.available ? '' : 'opacity-50 cursor-not-allowed'}
                `
                button.innerHTML = `
                    <div class="font-medium">${slot.time}</div>
                    <div class="text-xs text-gray-400 mt-1">
                        ${slot.available ? '可預約' : '已額滿'}
                    </div>
                `

                if (slot.available) {
                    button.addEventListener('click', () => this.selectTimeSlot(slot, button))
                } else {
                    button.disabled = true
                }

                slotsGrid.appendChild(button)
            })

            periodDiv.appendChild(slotsGrid)
            this.timeSlotsTarget.appendChild(periodDiv)
        })
    }

    groupTimeSlotsByPeriod(timeSlots) {
        return timeSlots.reduce((groups, slot) => {
            const period = slot.period_name || '用餐時段'
            if (!groups[period]) {
                groups[period] = []
            }
            groups[period].push(slot)
            return groups
        }, {})
    }

    updatePeriodInfo(businessPeriods) {
        if (!this.hasPeriodInfoTarget) return

        if (businessPeriods.length === 0) {
            this.periodInfoTarget.innerHTML = '<p class="text-gray-500">此日期未營業</p>'
            return
        }

        const periodsText = businessPeriods
            .map((period) => `${period.name}: ${period.start_time}-${period.end_time}`)
            .join('、')

        this.periodInfoTarget.innerHTML = `<p class="text-gray-400">可用餐期：${periodsText}</p>`
    }

    selectTimeSlot(slot, buttonElement) {
        console.log('🔥 Time slot selected:', slot)

        // 移除之前選中的樣式
        this.timeSlotsTarget.querySelectorAll('button').forEach((btn) => {
            btn.classList.remove('bg-blue-600', 'border-blue-500')
            btn.classList.add('bg-gray-800', 'border-gray-600')
        })

        // 添加選中樣式到當前按鈕
        buttonElement.classList.remove('bg-gray-800', 'border-gray-600')
        buttonElement.classList.add('bg-blue-600', 'border-blue-500')

        // 設置選中的值
        this.selectedTime = slot.time
        this.selectedPeriodId = slot.period_id

        // 設置隱藏欄位的值
        const timeField = document.getElementById('reservation_time')
        const periodField = document.getElementById('operating_period_id')

        if (timeField) timeField.value = slot.time
        if (periodField) periodField.value = slot.period_id

        this.updateFormState()
    }

    updateFormState() {
        if (!this.hasNextStepTarget) return

        const hasDate = this.selectedDate
        const hasTime = this.selectedTime

        if (hasDate && hasTime) {
            this.nextStepTarget.disabled = false
            this.nextStepTarget.classList.remove('bg-gray-600', 'hover:bg-gray-500')
            this.nextStepTarget.classList.add('bg-blue-600', 'hover:bg-blue-700')
        } else {
            this.nextStepTarget.disabled = true
            this.nextStepTarget.classList.remove('bg-blue-600', 'hover:bg-blue-700')
            this.nextStepTarget.classList.add('bg-gray-600', 'hover:bg-gray-500')
        }
    }

    showServiceUnavailable(message) {
        if (this.hasTimeSlotsTarget) {
            this.timeSlotsTarget.innerHTML = `
                <div class="bg-red-50 border border-red-200 rounded-lg p-6 text-center">
                    <div class="flex justify-center mb-4">
                        <svg class="h-12 w-12 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                        </svg>
                    </div>
                    <h3 class="text-lg font-medium text-red-800 mb-2">線上訂位暫停服務</h3>
                    <p class="text-red-700">${message}</p>
                </div>
            `
        }
    }

    showError(message) {
        console.error('🔥 Error:', message)
        if (this.hasTimeSlotsTarget) {
            this.timeSlotsTarget.innerHTML = `
                <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4 text-center">
                    <p class="text-yellow-800">${message}</p>
                </div>
            `
        }
    }

    calculateDisabledDates(weekly_closures, special_closures, hasCapacity = true) {
        const disabledDates = []

        // 如果沒有容量，禁用所有日期
        if (!hasCapacity) {
            const today = new Date()
            for (let i = 0; i <= this.maxReservationDays; i++) {
                const date = new Date(today)
                date.setDate(today.getDate() + i)
                disabledDates.push(date)
            }
            return disabledDates
        }

        // 處理每週固定休息日
        if (weekly_closures && weekly_closures.length > 0) {
            disabledDates.push((date) => {
                const dayOfWeek = date.getDay()
                return weekly_closures.includes(dayOfWeek)
            })
        }

        // 處理特殊休息日 - 將字串轉換為 Date 物件比較
        if (special_closures && special_closures.length > 0) {
            special_closures.forEach((closureStr) => {
                const closureDate = new Date(closureStr)
                // 比較年、月、日
                disabledDates.push((date) => {
                    return (
                        date.getFullYear() === closureDate.getFullYear() &&
                        date.getMonth() === closureDate.getMonth() &&
                        date.getDate() === closureDate.getDate()
                    )
                })
            })
        }

        return disabledDates
    }

    // 更新 URL，移除 show_all 參數並設定 date_filter
    updateUrlWithDate(dateStr) {
        const url = new URL(window.location)

        // 移除 show_all 參數
        url.searchParams.delete('show_all')

        // 設定 date_filter 參數
        url.searchParams.set('date_filter', dateStr)

        // 更新瀏覽器 URL，但不重新載入頁面
        window.history.pushState({}, '', url.toString())

        console.log('🔥 URL updated to:', url.toString())
    }

    clearSelectedTimeSlot() {
        // 清除選中的時段
        this.selectedTime = null
        this.selectedPeriodId = null

        // 清除視覺上的選中狀態
        if (this.hasTimeSlotsTarget) {
            this.timeSlotsTarget.querySelectorAll('button').forEach((btn) => {
                btn.classList.remove('bg-blue-600', 'border-blue-500')
                btn.classList.add('bg-gray-800', 'border-gray-600')
            })
        }

        // 清除隱藏欄位的值
        const timeField = document.getElementById('reservation_time')
        const periodField = document.getElementById('operating_period_id')

        if (timeField) timeField.value = ''
        if (periodField) periodField.value = ''

        // 更新表單狀態
        this.updateFormState()
    }

    async refreshAvailableDates() {
        console.log('🔥 Refreshing available dates due to party size change...')

        try {
            // 重新獲取可用日期資訊
            const partySize = this.getCurrentPartySize()
            const apiUrl = `/restaurants/${this.restaurantSlugValue}/available_days?party_size=${partySize}`
            console.log('🔥 Fetching updated available days from:', apiUrl)

            const response = await fetch(apiUrl, {
                headers: {
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                },
            })

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`)
            }

            const data = await response.json()
            console.log('🔥 Updated available days data:', data)

            // 重新計算禁用日期
            const disabledDates = this.calculateDisabledDates(
                data.weekly_closures || [],
                data.special_closures || [],
                data.has_capacity
            )

            // 更新 flatpickr 的禁用日期設定
            if (this.datePicker) {
                this.datePicker.set('disable', disabledDates)
                this.datePicker.redraw()
            }

            // 更新額滿提示訊息
            this.updateFullBookingNotice(data)

            // 如果當前選中的日期變成不可用，清除選擇
            if (this.selectedDate && !data.has_capacity) {
                console.log('🔥 Current selected date is no longer available, clearing selection')
                this.selectedDate = null
                if (this.hasDateTarget) {
                    this.dateTarget.value = ''
                }

                // 清除時段選擇
                if (this.hasTimeSlotsTarget) {
                    this.timeSlotsTarget.innerHTML = '<p class="text-gray-500 text-center py-4">請先選擇日期</p>'
                }
            }
        } catch (error) {
            console.error('🔥 Error refreshing available dates:', error)
            this.showError('重新載入可用日期時發生錯誤')
        }
    }
}
