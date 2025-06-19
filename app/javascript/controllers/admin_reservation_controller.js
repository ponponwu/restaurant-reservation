import { Controller } from '@hotwired/stimulus'
import flatpickr from 'flatpickr'
import zhTw from 'flatpickr/dist/l10n/zh-tw.js'

export default class extends Controller {
    static targets = [
        'calendar', 'dateField', 'businessPeriod', 'timeSlots', 'timeField', 
        'datetimeField', 'partySize', 'adultsCount', 'childrenCount',
        'forceMode', 'adminOverride'
    ]
    static values = {
        restaurantSlug: String
    }

    connect() {
        console.log('🔧 Admin reservation controller connected successfully!')
        console.log('🔧 Controller element:', this.element)
        console.log('🔧 Available targets:', this.targets)
        console.log('🔧 Has calendar target:', this.hasCalendarTarget)
        console.log('🔧 Calendar target element:', this.hasCalendarTarget ? this.calendarTarget : 'NOT FOUND')
        console.log('🔧 Restaurant slug:', this.restaurantSlugValue)
        
        // 檢查 flatpickr 是否可用
        console.log('🔧 Flatpickr available:', typeof flatpickr !== 'undefined')
        
        this.selectedDate = null
        this.selectedTime = null
        this.selectedPeriodId = null
        this.forceMode = false
        
        // 延遲初始化，確保 DOM 完全載入
        setTimeout(() => {
            console.log('🔧 Starting delayed initialization...')
            try {
                this.initDatePicker()
            } catch (error) {
                console.error('🔧 Error in initDatePicker:', error)
            }
        }, 300)
    }

    disconnect() {
        if (this.datePicker) {
            this.datePicker.destroy()
        }
    }

    initDatePicker() {
        console.log('🔧 Admin reservation: initializing date picker')
        
        if (!this.hasCalendarTarget) {
            console.error('🔧 No calendar target found!')
            return
        }

        // 銷毀現有的 flatpickr 實例
        if (this.datePicker) {
            this.datePicker.destroy()
            this.datePicker = null
        }

        // 管理後台直接使用基本日期選擇器
        this.initBasicDatePicker()
    }

    initBasicDatePicker() {
        console.log('🔧 Creating basic flatpickr instance')
        
        if (!this.hasCalendarTarget) {
            console.error('🔧 No calendar target found for basic picker!')
            return
        }

        try {
            const config = {
                inline: true,
                locale: zhTw.zh_tw,
                dateFormat: 'Y-m-d',
                minDate: 'today',
                maxDate: new Date().fp_incr(90), // 管理員可以選擇更遠的日期
                static: true, // 防止日曆被其他元素覆蓋
                onChange: (selectedDates, dateStr) => {
                    console.log('🔧 Basic picker date selected:', dateStr)
                    this.handleDateChange(dateStr)
                },
                onReady: () => {
                    console.log('🔧 Basic picker ready')
                    setTimeout(() => {
                        this.styleFlatpickr()
                    }, 50)
                },
                onError: (error) => {
                    console.error('🔧 Flatpickr error:', error)
                }
            }
            
            console.log('🔧 Creating flatpickr with config:', config)
            this.datePicker = flatpickr(this.calendarTarget, config)
            
            if (this.datePicker) {
                console.log('🔧 Basic picker created successfully:', this.datePicker)
            } else {
                console.error('🔧 Failed to create flatpickr instance')
            }
        } catch (error) {
            console.error('🔧 Error creating basic picker:', error)
        }
    }

    styleFlatpickr() {
        console.log('🔧 Styling flatpickr calendar for inline display')
        
        const calendarElement = this.calendarTarget.querySelector('.flatpickr-calendar')
        if (calendarElement) {
            console.log('🔧 Found calendar element, applying inline styling')
            
            // 基本定位和顯示（light theme is already applied via CSS import）
            calendarElement.classList.add('inline')
            calendarElement.style.position = 'relative'
            calendarElement.style.top = 'auto'
            calendarElement.style.left = 'auto'
            calendarElement.style.display = 'block'
            calendarElement.style.width = '100%'
            calendarElement.style.maxWidth = 'none'
            calendarElement.style.visibility = 'visible'
            calendarElement.style.opacity = '1'
            
            // 確保日期容器有正確的寬度
            const dayContainer = calendarElement.querySelector('.dayContainer')
            if (dayContainer) {
                dayContainer.style.width = '100%'
                dayContainer.style.minWidth = '100%'
                dayContainer.style.maxWidth = '100%'
            }
            
        } else {
            console.error('🔧 No calendar element found for styling')
        }
    }

    handleDateChange(dateStr) {
        this.selectedDate = dateStr
        
        // 更新隱藏的日期欄位
        if (this.hasDateFieldTarget) {
            this.dateFieldTarget.value = dateStr
        }
        
        // 清除之前選擇的時間
        this.clearTimeSelection()
        
        // 更新餐期選項
        this.updateBusinessPeriodOptions()
        
        // 直接載入所有時段（類似前台行為）
        this.loadAllTimeSlots(dateStr)
    }

    handlePeriodChange() {
        const selectedValue = this.businessPeriodTarget.value
        this.selectedPeriodId = selectedValue ? parseInt(selectedValue) : null
        
        console.log('🔧 Period selected:', this.selectedPeriodId)
        
        // 清除之前選擇的時間
        this.clearTimeSelection()
        
        // 如果已選擇日期和餐期，載入時間槽
        if (this.selectedDate && this.selectedPeriodId) {
            this.loadTimeSlots()
        } else {
            this.timeSlotsTarget.innerHTML = '<p class="text-gray-500 text-center py-4">請選擇餐期</p>'
        }
    }

    handlePartySizeChange() {
        console.log('🔧 Party size changed, refreshing date picker...')
        
        // 重新初始化日期選擇器（考慮新的人數）
        this.initDatePicker()
        
        // 如果已選擇日期和餐期，重新載入時間槽
        if (this.selectedDate && this.selectedPeriodId) {
            this.loadTimeSlots()
        }
    }

    async loadAllTimeSlots(date) {
        console.log('🔧 Loading all time slots for date:', date)

        if (!this.hasTimeSlotsTarget) {
            console.error('🔧 No timeSlots target found!')
            return
        }

        try {
            const partySize = this.getCurrentPartySize()
            const adults = this.hasAdultsCountTarget ? parseInt(this.adultsCountTarget.value) || 0 : partySize
            const children = this.hasChildrenCountTarget ? parseInt(this.childrenCountTarget.value) || 0 : 0

            const url = `/restaurants/${this.restaurantSlugValue}/reservations/available_slots?date=${date}&adult_count=${adults}&child_count=${children}`
            console.log('🔧 Fetching time slots from:', url)
            
            const response = await fetch(url, {
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json'
                }
            })

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`)
            }

            const data = await response.json()
            console.log('🔧 Time slots data:', data)

            this.renderAllTimeSlots(data.slots || [])
        } catch (error) {
            console.error('🔧 Error loading time slots:', error)
            this.timeSlotsTarget.innerHTML = `
                <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-center">
                    <p class="text-red-800">載入時間時發生錯誤</p>
                </div>
            `
        }
    }

    async loadTimeSlots() {
        if (!this.selectedDate || !this.selectedPeriodId) {
            return
        }

        console.log('🔧 Loading time slots for:', this.selectedDate, 'period:', this.selectedPeriodId)

        try {
            const partySize = this.getCurrentPartySize()
            const adults = this.hasAdultsCountTarget ? parseInt(this.adultsCountTarget.value) || 0 : partySize
            const children = this.hasChildrenCountTarget ? parseInt(this.childrenCountTarget.value) || 0 : 0

            const url = `/restaurants/${this.restaurantSlugValue}/reservations/available_slots?date=${this.selectedDate}&adult_count=${adults}&child_count=${children}`
            
            const response = await fetch(url, {
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json'
                }
            })

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`)
            }

            const data = await response.json()
            console.log('🔧 Time slots data:', data)

            // 過濾出指定餐期的時間槽
            const periodSlots = (data.slots || []).filter(slot => 
                slot.period_id === this.selectedPeriodId
            )

            this.renderTimeSlots(periodSlots)
        } catch (error) {
            console.error('🔧 Error loading time slots:', error)
            this.timeSlotsTarget.innerHTML = `
                <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-center">
                    <p class="text-red-800">載入時間時發生錯誤</p>
                </div>
            `
        }
    }

    renderAllTimeSlots(timeSlots) {
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
            periodTitle.className = 'text-gray-700 font-medium mb-3 flex items-center'
            periodTitle.innerHTML = `
                <span class="w-2 h-2 bg-blue-500 rounded-full mr-2"></span>
                ${periodName}
            `
            periodDiv.appendChild(periodTitle)

            const slotsGrid = document.createElement('div')
            slotsGrid.className = 'grid grid-cols-3 gap-3'

            slots.forEach((slot) => {
                const button = document.createElement('button')
                button.type = 'button'
                
                // 管理員強制模式下，所有時間槽都可以點擊
                const canSelect = slot.available || this.forceMode
                
                button.className = `
                    border rounded-lg px-3 py-2 text-sm text-center transition-colors
                    focus:outline-none focus:ring-2 focus:ring-blue-500
                    ${slot.available 
                        ? 'bg-white border-gray-300 text-gray-700 hover:bg-gray-50' 
                        : this.forceMode 
                            ? 'bg-red-50 border-red-300 text-red-700 hover:bg-red-100'
                            : 'bg-gray-100 border-gray-200 text-gray-400 cursor-not-allowed'
                    }
                `
                button.innerHTML = `
                    <div class="font-medium">${slot.time}</div>
                    <div class="text-xs mt-1">
                        ${slot.available 
                            ? '可預約' 
                            : this.forceMode 
                                ? '已滿(強制)'
                                : '已額滿'
                        }
                    </div>
                `

                if (canSelect) {
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

    renderTimeSlots(slots) {
        if (slots.length === 0) {
            this.timeSlotsTarget.innerHTML = `
                <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4 text-center">
                    <p class="text-yellow-800">此日期此餐期無可用時間</p>
                </div>
            `
            return
        }

        const slotsGrid = document.createElement('div')
        slotsGrid.className = 'grid grid-cols-3 gap-3'

        slots.forEach(slot => {
            const button = document.createElement('button')
            button.type = 'button'
            
            // 管理員強制模式下，所有時間槽都可以點擊
            const canSelect = slot.available || this.forceMode
            
            button.className = `
                border rounded-lg px-3 py-2 text-sm text-center transition-colors
                focus:outline-none focus:ring-2 focus:ring-blue-500
                ${slot.available 
                    ? 'bg-white border-gray-300 text-gray-700 hover:bg-gray-50' 
                    : this.forceMode 
                        ? 'bg-red-50 border-red-300 text-red-700 hover:bg-red-100'
                        : 'bg-gray-100 border-gray-200 text-gray-400 cursor-not-allowed'
                }
            `
            
            button.innerHTML = `
                <div class="font-medium">${slot.time}</div>
                <div class="text-xs mt-1">
                    ${slot.available 
                        ? '可預約' 
                        : this.forceMode 
                            ? '已滿(強制)'
                            : '已額滿'
                    }
                </div>
            `

            if (canSelect) {
                button.addEventListener('click', () => this.selectTimeSlot(slot, button))
            } else {
                button.disabled = true
            }

            slotsGrid.appendChild(button)
        })

        this.timeSlotsTarget.innerHTML = ''
        this.timeSlotsTarget.appendChild(slotsGrid)
    }

    selectTimeSlot(slot, buttonElement) {
        console.log('🔧 Time slot selected:', slot)

        // 移除之前選中的樣式
        this.timeSlotsTarget.querySelectorAll('button').forEach(btn => {
            btn.classList.remove('bg-blue-600', 'border-blue-500', 'text-white')
            // 恢復原本的樣式
            if (slot.available) {
                btn.classList.add('bg-white', 'border-gray-300', 'text-gray-700')
            } else {
                btn.classList.add('bg-red-50', 'border-red-300', 'text-red-700')
            }
        })

        // 添加選中樣式
        buttonElement.classList.remove('bg-white', 'border-gray-300', 'text-gray-700', 'bg-red-50', 'border-red-300', 'text-red-700')
        buttonElement.classList.add('bg-blue-600', 'border-blue-500', 'text-white')

        // 設置選中的值
        this.selectedTime = slot.time
        
        // 更新隱藏欄位
        if (this.hasTimeFieldTarget) {
            this.timeFieldTarget.value = slot.time
        }
        
        // 設置管理員強制模式標記
        if (this.hasAdminOverrideTarget) {
            this.adminOverrideTarget.value = this.forceMode && !slot.available ? 'true' : 'false'
        }
        
        // 組合完整的日期時間
        this.updateDateTimeField()
    }

    updateDateTimeField() {
        console.log('🔧 Updating datetime field:', {
            selectedDate: this.selectedDate,
            selectedTime: this.selectedTime,
            hasDatetimeField: this.hasDatetimeFieldTarget
        })
        
        if (this.selectedDate && this.selectedTime && this.hasDatetimeFieldTarget) {
            const fullDateTime = `${this.selectedDate}T${this.selectedTime}`
            this.datetimeFieldTarget.value = fullDateTime
            console.log('🔧 Updated datetime field:', fullDateTime)
            
            // 觸發 change 事件以便其他控制器能夠響應
            this.datetimeFieldTarget.dispatchEvent(new Event('change'))
        } else {
            console.log('🔧 Cannot update datetime field - missing data or target')
        }
    }

    clearTimeSelection() {
        this.selectedTime = null
        
        if (this.hasTimeFieldTarget) {
            this.timeFieldTarget.value = ''
        }
        
        if (this.hasTimeSlotsTarget) {
            this.timeSlotsTarget.innerHTML = '<p class="text-gray-500 text-center py-4">請選擇餐期</p>'
        }
    }

    updateBusinessPeriodOptions() {
        // 這裡可以根據選擇的日期動態更新餐期選項
        // 目前先保持現有的選項
        if (this.hasBusinessPeriodTarget) {
            // 啟用餐期選擇
            this.businessPeriodTarget.disabled = false
        }
    }

    getCurrentPartySize() {
        return this.hasPartySizeTarget ? parseInt(this.partySizeTarget.value) || 2 : 2
    }

    calculateDisabledDates(weekly_closures, special_closures, hasCapacity = true) {
        const disabledDates = []

        // 如果沒有容量，禁用所有日期
        if (!hasCapacity) {
            const today = new Date()
            for (let i = 0; i <= 30; i++) {
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

        // 處理特殊休息日
        if (special_closures && special_closures.length > 0) {
            special_closures.forEach((closureStr) => {
                const closureDate = new Date(closureStr)
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

    toggleForceMode() {
        this.forceMode = this.hasForceModeTarget ? this.forceModeTarget.checked : false
        console.log('🔧 Force mode toggled:', this.forceMode)
        
        // 重新渲染時間槽
        if (this.selectedDate && this.selectedPeriodId) {
            this.loadTimeSlots()
        }
    }
}