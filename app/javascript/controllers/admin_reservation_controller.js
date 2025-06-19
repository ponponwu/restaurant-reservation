import { Controller } from '@hotwired/stimulus'
import flatpickr from 'flatpickr'
import zhTw from 'flatpickr/dist/l10n/zh-tw.js'

export default class extends Controller {
    static targets = [
        'calendar',
        'dateField',
        'timeField',
        'datetimeField',
        'partySize',
        'adultsCount',
        'childrenCount',
        'forceMode',
        'adminOverride',
        'businessPeriodField',
        'businessPeriodHint',
        'businessPeriodTime',
    ]
    static values = {
        restaurantSlug: String,
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
                },
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

        // 更新日期時間欄位
        this.updateDateTimeField()
    }

    handleTimeChange() {
        const timeValue = this.timeFieldTarget.value
        this.selectedTime = timeValue

        console.log('🔧 Time changed:', timeValue)

        // 更新日期時間欄位
        this.updateDateTimeField()
    }

    handlePartySizeChange() {
        console.log('🔧 Party size changed, refreshing date picker...')

        // 重新初始化日期選擇器（考慮新的人數）
        this.initDatePicker()
    }

    updateDateTimeField() {
        console.log('🔧 Updating datetime field:', {
            selectedDate: this.selectedDate,
            selectedTime: this.selectedTime,
            hasDatetimeField: this.hasDatetimeFieldTarget,
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

    getCurrentPartySize() {
        return this.hasPartySizeTarget ? parseInt(this.partySizeTarget.value) || 2 : 2
    }

    toggleForceMode() {
        this.forceMode = this.hasForceModeTarget ? this.forceModeTarget.checked : false
        console.log('🔧 Force mode toggled:', this.forceMode)

        // 設置管理員強制模式標記
        if (this.hasAdminOverrideTarget) {
            this.adminOverrideTarget.value = this.forceMode ? 'true' : 'false'
        }
    }

    handleBusinessPeriodChange() {
        console.log('🔧 Business period changed')

        if (!this.hasBusinessPeriodFieldTarget) {
            console.error('🔧 No business period field target found')
            return
        }

        const selectedOption = this.businessPeriodFieldTarget.selectedOptions[0]

        if (selectedOption && selectedOption.value) {
            console.log('🔧 Selected business period:', selectedOption.text)

            // 顯示餐期時間範圍提示
            if (this.hasBusinessPeriodHintTarget && this.hasBusinessPeriodTimeTarget) {
                this.businessPeriodTimeTarget.textContent = selectedOption.text
                this.businessPeriodHintTarget.classList.remove('hidden')
            }

            // 可以在這裡添加更多邏輯，比如自動設定時間範圍
            this.setDefaultTimeForPeriod(selectedOption.text)
        } else {
            // 隱藏提示
            if (this.hasBusinessPeriodHintTarget) {
                this.businessPeriodHintTarget.classList.add('hidden')
            }
        }
    }

    setDefaultTimeForPeriod(periodText) {
        // 從餐期文字中提取時間範圍（格式如：午餐 (11:30 - 14:30)）
        const timeMatch = periodText.match(/\((\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})\)/)

        if (timeMatch && this.hasTimeFieldTarget) {
            const startTime = timeMatch[1]
            // 設定為餐期開始時間後30分鐘
            const [hours, minutes] = startTime.split(':')
            const startDate = new Date()
            startDate.setHours(parseInt(hours), parseInt(minutes) + 30)

            const defaultTime = startDate.toTimeString().slice(0, 5)
            this.timeFieldTarget.value = defaultTime
            this.selectedTime = defaultTime

            console.log('🔧 Set default time for period:', defaultTime)
            this.updateDateTimeField()
        }
    }
}
