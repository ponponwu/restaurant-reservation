import { Controller } from '@hotwired/stimulus'
import flatpickr from 'flatpickr'
import zhTw from 'flatpickr/dist/l10n/zh-tw.js'

export default class extends Controller {
    static targets = [
        'date',
        'calendar',
        'timeSlots',
        'periodInfo',
        'nextStep',
        'adultCount',
        'childCount',
        'fullBookingNotice',
        'datePickerContainer',
    ]
    static values = {
        restaurantSlug: String,
        businessHours: Object,
        maxPartySize: Number,
        minPartySize: Number,
    }

    connect() {

        this.selectedDate = null
        this.selectedPeriodId = null
        this.selectedTime = null
        this.maxReservationDays = 30 // 預設值，將從 API 獲取實際值

        // 監聽窗口大小變化，重新應用縮放（使用防抖動）
        this.resizeTimeout = null
        this.resizeHandler = () => {
            clearTimeout(this.resizeTimeout)
            this.resizeTimeout = setTimeout(() => {
                const calendarElement = this.calendarTarget?.querySelector('.flatpickr-calendar')
                if (calendarElement) {
                    this.applyResponsiveScale(calendarElement)
                }
            }, 150) // 防抖動延遲
        }
        window.addEventListener('resize', this.resizeHandler)

        // 也監聽 orientationchange 事件（手機旋轉）
        window.addEventListener('orientationchange', () => {
            setTimeout(() => {
                const calendarElement = this.calendarTarget?.querySelector('.flatpickr-calendar')
                if (calendarElement) {
                    this.applyResponsiveScale(calendarElement)
                }
            }, 300)
        })

        // 延遲初始化，確保 DOM 完全載入
        setTimeout(() => {
            this.initDatePicker()
            this.setupGuestCountListeners()
            this.updateGuestCountOptions() // 初始化人數選項
        }, 100)
    }

    disconnect() {
        // 清理事件監聽器
        if (this.resizeHandler) {
            window.removeEventListener('resize', this.resizeHandler)
        }

        // 清理防抖動計時器
        if (this.resizeTimeout) {
            clearTimeout(this.resizeTimeout)
        }
    }

    setupGuestCountListeners() {
        const handleGuestCountChange = () => {

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

    }

    validateCurrentSelection() {
        const adults = parseInt(this.adultCountTarget.value) || 1
        const children = parseInt(this.childCountTarget.value) || 0
        const totalPartySize = adults + children
        const maxPartySize = this.maxPartySizeValue || 6

        // 如果總人數超過上限，調整小孩數
        if (totalPartySize > maxPartySize) {
            const adjustedChildren = Math.max(0, maxPartySize - adults)
            this.childCountTarget.value = adjustedChildren

            // 重新更新選項以反映新的狀態
            setTimeout(() => this.updateGuestCountOptions(), 10)
        }

        // 如果大人數為0，調整為1
        if (adults < 1) {
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
        if (!this.hasCalendarTarget) {
            console.error('No calendar target found')
            return
        }

        // 銷毀現有的 flatpickr 實例
        if (this.datePicker) {
            this.datePicker.destroy()
            this.datePicker = null
        }

        try {
            // 先檢查是否有可用日期 (使用 available_dates 端點)
            const partySize = this.getCurrentPartySize()
            const adults = this.hasAdultCountTarget ? parseInt(this.adultCountTarget.value) || 0 : partySize
            const children = this.hasChildCountTarget ? parseInt(this.childCountTarget.value) || 0 : 0

            const availableDatesUrl = `/restaurants/${this.restaurantSlugValue}/available_dates?party_size=${partySize}&adults=${adults}&children=${children}`

            const availableDatesResponse = await fetch(availableDatesUrl, {
                headers: {
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                },
            })

            if (availableDatesResponse.status === 503) {
                const errorData = await availableDatesResponse.json()
                this.showServiceUnavailable(errorData.message || errorData.error)
                return
            }

            if (!availableDatesResponse.ok) {
                throw new Error(`HTTP error! status: ${availableDatesResponse.status}`)
            }

            const availableDatesData = await availableDatesResponse.json()

            // 檢查是否完全沒有可用日期
            if (
                availableDatesData.has_capacity &&
                availableDatesData.available_dates.length === 0 &&
                availableDatesData.full_booked_until
            ) {
                this.showFullyBookedMessage(availableDatesData.full_booked_until, partySize)
                return
            }

            // 如果有可用日期，繼續載入日曆
            // 取得可預約日資訊 (使用 available_days 端點取得詳細的禁用日期)
            const apiUrl = `/restaurants/${this.restaurantSlugValue}/available_days?party_size=${partySize}`

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

            // 隱藏完全訂滿訊息，顯示日曆
            this.hideFullyBookedMessage()

            // 計算不可用日期 - 使用新的 API 回應格式，並傳入實際可預約日期
            const disabledDates = this.calculateDisabledDates(
                data.weekly_closures || [],
                data.special_closures || [],
                data.has_capacity,
                availableDatesData.available_dates || []
            )

            // 決定日曆的預設日期和顯示月份
            let defaultDate = null
            let defaultViewDate = null
            
            if (availableDatesData.available_dates && availableDatesData.available_dates.length > 0) {
                // 使用第一個可預約日期作為預設日期
                defaultDate = availableDatesData.available_dates[0]
                defaultViewDate = new Date(defaultDate)
            }


            // 初始化 flatpickr
            const flatpickrConfig = {
                inline: true,
                static: true,
                // 移除 appendTo，讓 flatpickr 使用預設行為
                locale: zhTw.zh_tw,
                dateFormat: 'Y-m-d',
                minDate: 'today',
                maxDate: new Date().fp_incr(this.maxReservationDays),
                disable: disabledDates,
                // 如果有可預約日期，設定預設日期和視圖月份
                ...(defaultDate && { defaultDate: defaultDate }),
                ...(defaultViewDate && { defaultViewDate: defaultViewDate }),
                onChange: (selectedDates, dateStr) => {
                    this.selectedDate = dateStr

                    // 更新 JavaScript target 欄位
                    if (this.hasDateTarget) {
                        this.dateTarget.value = dateStr
                    }
                    
                    // 同時更新表單提交的隱藏欄位
                    const reservationDateField = document.getElementById('reservation_date')
                    if (reservationDateField) {
                        reservationDateField.value = dateStr
                    }

                    // 更新 URL，移除 show_all 參數並設定 date_filter
                    this.updateUrlWithDate(dateStr)

                    this.loadAllTimeSlots(dateStr)
                },
                onReady: (selectedDates, dateStr, instance) => {
                    setTimeout(() => this.styleFlatpickr(), 100)
                    
                    // 在 onReady 中，instance 就是 flatpickr 實例
                    if (defaultDate && instance) {
                        setTimeout(() => {
                            // 使用 instance.setDate 而不是 this.datePicker.setDate
                            instance.setDate(defaultDate, true)
                            
                            // 備份機制：如果 onChange 沒有正常觸發，手動載入時段
                            setTimeout(() => {
                                if (this.hasTimeSlotsTarget) {
                                    const currentTimeSlots = this.timeSlotsTarget.innerHTML.trim()
                                    if (!currentTimeSlots || 
                                        currentTimeSlots.includes('請先選擇日期') || 
                                        currentTimeSlots === '') {
                                        this.selectedDate = defaultDate // 手動設定
                                        this.loadAllTimeSlots(defaultDate)
                                    }
                                }
                            }, 100)
                        }, 300) // 增加延遲確保 DOM 準備完成
                    }
                },
                onOpen: () => {
                    // 確保在日曆打開時也應用樣式（雖然我們使用 inline 模式，但保險起見）
                    setTimeout(() => this.styleFlatpickr(), 100)
                },
                onMonthChange: () => {
                    // 確保在月份切換時也重新應用樣式
                    setTimeout(() => this.styleFlatpickr(), 50)
                },
                onYearChange: () => {
                    // 確保在年份切換時也重新應用樣式
                    setTimeout(() => this.styleFlatpickr(), 50)
                },
            }
            
            this.datePicker = flatpickr(this.calendarTarget, flatpickrConfig)

        } catch (error) {
            console.error('Error initializing date picker:', error)
            this.showError('載入日期選擇器時發生錯誤')
        }
    }

    styleFlatpickr(retryCount = 0) {
        // 嘗試在 calendarTarget 內部和整個文檔中查找
        let calendarElement = this.calendarTarget?.querySelector('.flatpickr-calendar')
        if (!calendarElement) {
            calendarElement = document.querySelector('.flatpickr-calendar')
        }

        if (!calendarElement) {
            if (retryCount < 3) {
                setTimeout(() => this.styleFlatpickr(retryCount + 1), 200)
            }
            return
        }

        // 確保日曆是 inline 模式
        calendarElement.classList.add('inline')

        // 移除可能衝突的內聯樣式，讓CSS生效
        calendarElement.style.position = 'relative'
        calendarElement.style.top = ''
        calendarElement.style.left = ''
        calendarElement.style.display = 'block'
        calendarElement.style.width = '100%'
        calendarElement.style.maxWidth = '100%'

        // 確保 transform 樣式不會被覆蓋
        calendarElement.style.transformOrigin = 'center center'

        // 強制應用等比例放大樣式
        this.applyResponsiveScale(calendarElement)

        // 讓dayContainer使用CSS設定
        const dayContainer = calendarElement.querySelector('.dayContainer')
        if (dayContainer) {
            dayContainer.style.width = ''
            dayContainer.style.minWidth = ''
            dayContainer.style.maxWidth = ''
        }

        // 讓days容器使用CSS設定
        const daysContainer = calendarElement.querySelector('.flatpickr-days')
        if (daysContainer) {
            daysContainer.style.width = ''
        }

    }

    applyResponsiveScale(calendarElement) {
        const screenWidth = window.innerWidth
        let scale, margin, maxWidth

        // 配合 CSS 斷點的響應式縮放
        if (screenWidth <= 480) {
            // 極小螢幕 - 手機直向
            scale = 1.2
            margin = '1rem auto'
            maxWidth = '100%'
        } else if (screenWidth <= 768) {
            // 小螢幕 - 手機橫向/小平板
            scale = 1.1
            margin = '1rem auto'
            maxWidth = '90%'
        } else if (screenWidth <= 1024) {
            // 中等螢幕 - 平板
            scale = 1.1
            margin = '1.25rem auto'
            maxWidth = '100%'
        } else if (screenWidth <= 1440) {
            // 大螢幕 - 桌機
            scale = 1.2
            margin = '2rem auto'
            maxWidth = '100%'
        } else {
            // 超大螢幕 - 大桌機
            scale = 1.3
            margin = '2rem auto'
            maxWidth = '100%'
        }

        // 應用縮放和邊距
        calendarElement.style.transform = `scale(${scale})`
        calendarElement.style.webkitTransform = `scale(${scale})`
        calendarElement.style.mozTransform = `scale(${scale})`
        calendarElement.style.msTransform = `scale(${scale})`
        calendarElement.style.margin = margin
        calendarElement.style.maxWidth = maxWidth
    }

    updateFullBookingNotice(data) {
        // 簡化邏輯：不顯示額滿提示訊息
        if (this.hasFullBookingNoticeTarget) {
            this.fullBookingNoticeTarget.classList.add('hidden')
        }
    }

    showFullyBookedMessage(fullBookedUntil, partySize) {

        // 隱藏日曆
        if (this.hasDatePickerContainerTarget) {
            this.datePickerContainerTarget.classList.add('hidden')
        }

        // 隱藏時間選擇區域
        if (this.hasTimeSlotsTarget) {
            this.timeSlotsTarget.innerHTML = ''
        }

        // 顯示完全訂滿訊息
        if (this.hasFullBookingNoticeTarget) {
            const formattedDate = this.formatDateToTaiwan(fullBookedUntil)
            this.fullBookingNoticeTarget.innerHTML = `
                <div class="bg-gray-800 border border-gray-600 rounded-lg p-6 text-center">
                    <div class="flex justify-center mb-4">
                        <svg class="h-12 w-12 text-orange-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
                        </svg>
                    </div>
                    <h3 class="text-lg font-semibold text-white mb-2">訂位已額滿</h3>
                    <p class="text-gray-300">到 ${formattedDate} 為止 ${partySize} 人訂位已額滿</p>
                    <p class="text-gray-400 text-sm mt-2">請嘗試調整人數或直接聯絡餐廳</p>
                </div>
            `
            this.fullBookingNoticeTarget.classList.remove('hidden')
        }

        // 禁用下一步按鈕
        if (this.hasNextStepTarget) {
            this.nextStepTarget.disabled = true
            this.nextStepTarget.classList.remove('bg-blue-600', 'hover:bg-blue-700')
            this.nextStepTarget.classList.add('bg-gray-600', 'hover:bg-gray-500')
        }
    }

    hideFullyBookedMessage() {

        // 顯示日曆
        if (this.hasDatePickerContainerTarget) {
            this.datePickerContainerTarget.classList.remove('hidden')
        }

        // 隱藏完全訂滿訊息
        if (this.hasFullBookingNoticeTarget) {
            this.fullBookingNoticeTarget.classList.add('hidden')
        }
    }

    formatDateToTaiwan(dateString) {
        try {
            const date = new Date(dateString)
            const year = date.getFullYear()
            const month = date.getMonth() + 1
            const day = date.getDate()
            return `${year}年${month}月${day}日`
        } catch (error) {
            console.error('Error formatting date:', error)
            return dateString
        }
    }

    async loadAllTimeSlots(date) {
        if (!this.hasTimeSlotsTarget) {
            console.error('No timeSlots target found')
            return
        }

        try {
            const partySize = this.getCurrentPartySize()
            const adults = this.hasAdultCountTarget ? parseInt(this.adultCountTarget.value) || 0 : partySize
            const children = this.hasChildCountTarget ? parseInt(this.childCountTarget.value) || 0 : 0

            const url = `/restaurants/${this.restaurantSlugValue}/reservations/available_slots?date=${date}&adult_count=${adults}&child_count=${children}`

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

            this.renderTimeSlots(data.slots || [])
            this.updateFormState()
        } catch (error) {
            console.error('Error loading time slots:', error)
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
        if (this.hasTimeSlotsTarget) {
            this.timeSlotsTarget.innerHTML = `
                <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4 text-center">
                    <p class="text-yellow-800">${message}</p>
                </div>
            `
        }
    }

    calculateDisabledDates(weekly_closures, special_closures, hasCapacity = true, availableDates = []) {
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

        // 如果有提供可預約日期列表，只允許該列表中的日期可點擊
        if (availableDates && availableDates.length > 0) {
            // 將可預約日期字串轉換為 Date 物件集合
            const availableDateSet = new Set(availableDates.map(dateStr => {
                const date = new Date(dateStr)
                return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
            }))
            
            // 添加函數來禁用不在可預約列表中的日期
            disabledDates.push((date) => {
                const dateStr = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
                return !availableDateSet.has(dateStr)
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

        try {
            // 先檢查是否有可用日期
            const partySize = this.getCurrentPartySize()
            const adults = this.hasAdultCountTarget ? parseInt(this.adultCountTarget.value) || 0 : partySize
            const children = this.hasChildCountTarget ? parseInt(this.childCountTarget.value) || 0 : 0

            const availableDatesUrl = `/restaurants/${this.restaurantSlugValue}/available_dates?party_size=${partySize}&adults=${adults}&children=${children}`

            const availableDatesResponse = await fetch(availableDatesUrl, {
                headers: {
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                },
            })

            if (!availableDatesResponse.ok) {
                throw new Error(`HTTP error! status: ${availableDatesResponse.status}`)
            }

            const availableDatesData = await availableDatesResponse.json()

            // 檢查是否完全沒有可用日期
            if (
                availableDatesData.has_capacity &&
                availableDatesData.available_dates.length === 0 &&
                availableDatesData.full_booked_until
            ) {
                // 銷毀現有的 flatpickr 實例
                if (this.datePicker) {
                    this.datePicker.destroy()
                    this.datePicker = null
                }
                this.showFullyBookedMessage(availableDatesData.full_booked_until, partySize)
                return
            }

            // 如果有可用日期，確保日曆是顯示的
            this.hideFullyBookedMessage()

            // 重新獲取可用日期資訊
            const apiUrl = `/restaurants/${this.restaurantSlugValue}/available_days?party_size=${partySize}`

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

            // 重新計算禁用日期
            const disabledDates = this.calculateDisabledDates(
                data.weekly_closures || [],
                data.special_closures || [],
                data.has_capacity,
                availableDatesData.available_dates || []
            )

            // 更新 flatpickr 的禁用日期設定
            if (this.datePicker) {
                this.datePicker.set('disable', disabledDates)
                this.datePicker.redraw()
                // 重新應用樣式，因為 redraw 可能會重置樣式
                setTimeout(() => this.styleFlatpickr(), 50)
            } else {
                // 如果沒有 datePicker 實例，重新初始化
                this.initDatePicker()
                return
            }

            // 如果當前選中的日期變成不可用，清除選擇
            if (this.selectedDate && !data.has_capacity) {
                this.selectedDate = null
                if (this.hasDateTarget) {
                    this.dateTarget.value = ''
                }
                
                // 同時清除表單提交的隱藏欄位
                const reservationDateField = document.getElementById('reservation_date')
                if (reservationDateField) {
                    reservationDateField.value = ''
                }

                // 清除時段選擇
                if (this.hasTimeSlotsTarget) {
                    this.timeSlotsTarget.innerHTML = '<p class="text-gray-500 text-center py-4">請先選擇日期</p>'
                }
            }
        } catch (error) {
            console.error('Error refreshing available dates:', error)
            this.showError('重新載入可用日期時發生錯誤')
        }
    }
}
