import { Controller } from '@hotwired/stimulus'
import flatpickr from 'flatpickr'
import zhTw from 'flatpickr/dist/l10n/zh-tw.js'
import 'flatpickr/dist/flatpickr.css'

export default class extends Controller {
    static targets = ['date', 'timeSlots', 'periodInfo', 'nextStep', 'adultCount', 'childCount']
    static values = {
        restaurantSlug: String,
        businessHours: Object,
    }

    connect() {
        console.log('🔥 Reservation controller connected')
        console.log('🔥 Controller targets:', this.targets)
        console.log('🔥 timeSlots target available:', this.hasTimeSlotsTarget)
        console.log('🔥 dateTarget available:', this.hasDateTarget)
        console.log('🔥 Restaurant slug:', this.restaurantSlugValue)

        this.selectedDate = null
        this.selectedPeriodId = null
        this.selectedTime = null
        this.maxReservationDays = 30 // 預設值，將從 API 獲取實際值

        // 延遲初始化，確保 DOM 完全載入
        setTimeout(() => {
            this.initDatePicker()
            this.setupGuestCountListeners()
        }, 100)
    }

    setupGuestCountListeners() {
        // 監聽成人人數變化
        if (this.hasAdultCountTarget) {
            this.adultCountTarget.addEventListener('change', () => {
                // 更新隱藏欄位
                const adultHiddenField = document.getElementById('adult_count')
                if (adultHiddenField) {
                    adultHiddenField.value = this.adultCountTarget.value
                }

                if (this.selectedDate) {
                    this.loadAllTimeSlots(this.selectedDate)
                }
            })
        } else {
            // 如果沒有指定 target，使用選擇器查詢
            const adultSelect = document.querySelector('[name="reservation[adult_count]"]')
            if (adultSelect) {
                adultSelect.addEventListener('change', () => {
                    // 更新隱藏欄位
                    const adultHiddenField = document.getElementById('adult_count')
                    if (adultHiddenField) {
                        adultHiddenField.value = adultSelect.value
                    }

                    if (this.selectedDate) {
                        this.loadAllTimeSlots(this.selectedDate)
                    }
                })
            }
        }

        // 監聽兒童人數變化
        if (this.hasChildCountTarget) {
            this.childCountTarget.addEventListener('change', () => {
                // 更新隱藏欄位
                const childHiddenField = document.getElementById('child_count')
                if (childHiddenField) {
                    childHiddenField.value = this.childCountTarget.value
                }

                if (this.selectedDate) {
                    this.loadAllTimeSlots(this.selectedDate)
                }
            })
        } else {
            // 如果沒有指定 target，使用選擇器查詢
            const childSelect = document.querySelector('[name="reservation[child_count]"]')
            if (childSelect) {
                childSelect.addEventListener('change', () => {
                    // 更新隱藏欄位
                    const childHiddenField = document.getElementById('child_count')
                    if (childHiddenField) {
                        childHiddenField.value = childSelect.value
                    }

                    if (this.selectedDate) {
                        this.loadAllTimeSlots(this.selectedDate)
                    }
                })
            }
        }

        // 初始化時設置隱藏欄位
        const adultHiddenField = document.getElementById('adult_count')
        const childHiddenField = document.getElementById('child_count')
        const adultSelect = this.hasAdultCountTarget
            ? this.adultCountTarget
            : document.querySelector('[name="reservation[adult_count]"]')
        const childSelect = this.hasChildCountTarget
            ? this.childCountTarget
            : document.querySelector('[name="reservation[child_count]"]')

        if (adultHiddenField && adultSelect) {
            adultHiddenField.value = adultSelect.value
        }

        if (childHiddenField && childSelect) {
            childHiddenField.value = childSelect.value
        }
    }

    async initDatePicker() {
        console.log('🔥 Starting initDatePicker...')

        if (!this.hasDateTarget) {
            console.error('🔥 No dateTarget found!')
            return
        }

        console.log('🔥 dateTarget element:', this.dateTarget)

        try {
            // 取得後端可預約日資訊 (調整為當前專案的 API 端點)
            const apiUrl = `/restaurants/${this.restaurantSlugValue}/available_days`
            console.log('🔥 Fetching from:', apiUrl)

            const response = await fetch(apiUrl)
            console.log('🔥 API response status:', response.status)

            // 檢查是否是訂位功能關閉的回應
            if (response.status === 503) {
                const errorData = await response.json()
                console.log('🔥 Reservation service unavailable:', errorData)

                // 顯示訂位功能停用的訊息
                if (this.hasTimeSlotsTarget) {
                    this.timeSlotsTarget.innerHTML = `
                        <div class="bg-red-50 border border-red-200 rounded-lg p-6 text-center">
                            <div class="flex justify-center mb-4">
                                <svg class="h-12 w-12 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                                </svg>
                            </div>
                            <h3 class="text-lg font-medium text-red-800 mb-2">線上訂位暫停服務</h3>
                            <p class="text-red-700">${errorData.message || errorData.error}</p>
                        </div>
                    `
                }

                // 隱藏日期選擇器
                if (this.hasDateTarget) {
                    this.dateTarget.style.display = 'none'
                }

                return
            }

            if (!response.ok) {
                throw new Error(`API request failed: ${response.status}`)
            }

            const availableDays = await response.json()
            console.log('🔥 Available days data:', availableDays)
            const weekly = availableDays.weekly
            const special = availableDays.special

            // 從 API 獲取最大預訂天數
            this.maxReservationDays = availableDays.max_days || 30
            console.log('餐廳最大預訂天數:', this.maxReservationDays)

            // 獲取預訂情況 (調整為當前專案的 API 端點)
            const availabilityResponse = await fetch(
                `/restaurants/${this.restaurantSlugValue}/reservations/availability_status`
            )

            // 檢查第二個 API 是否也是訂位功能關閉
            if (availabilityResponse.status === 503) {
                const errorData = await availabilityResponse.json()
                console.log('🔥 Availability service unavailable:', errorData)

                // 顯示訂位功能停用的訊息
                if (this.hasTimeSlotsTarget) {
                    this.timeSlotsTarget.innerHTML = `
                        <div class="bg-red-50 border border-red-200 rounded-lg p-6 text-center">
                            <div class="flex justify-center mb-4">
                                <svg class="h-12 w-12 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                                </svg>
                            </div>
                            <h3 class="text-lg font-medium text-red-800 mb-2">線上訂位暫停服務</h3>
                            <p class="text-red-700">${errorData.message || errorData.error}</p>
                        </div>
                    `
                }

                // 隱藏日期選擇器
                if (this.hasDateTarget) {
                    this.dateTarget.style.display = 'none'
                }

                return
            }

            const availabilityData = await availabilityResponse.json()

            // 顯示預訂全滿的提示
            if (availabilityData.fully_booked_until) {
                const fullyBookedDate = new Date(availabilityData.fully_booked_until)
                const formattedDate = fullyBookedDate.toLocaleDateString('zh-TW', {
                    year: 'numeric',
                    month: 'long',
                    day: 'numeric',
                })

                // 在日期選擇器上方添加提示
                const dateContainer = this.dateTarget.closest('div')
                const noticeDiv = document.createElement('div')
                noticeDiv.className = 'bg-yellow-100 border-l-4 border-yellow-500 text-yellow-700 p-4 mb-4'
                noticeDiv.innerHTML = `
                    <div class="flex">
                        <div class="flex-shrink-0">
                            <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                                <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                            </svg>
                        </div>
                        <div class="ml-3">
                            <p class="text-sm">目前預訂已滿至 ${formattedDate}，請選擇之後的日期。</p>
                        </div>
                    </div>
                `
                dateContainer.insertBefore(noticeDiv, this.dateTarget)
            }

            if (this.hasDateTarget) {
                // 計算需要 disable 的日期
                const disableDates = []
                const today = new Date()
                const endDate = new Date()
                endDate.setDate(today.getDate() + this.maxReservationDays)

                for (let date = new Date(today); date <= endDate; date.setDate(date.getDate() + 1)) {
                    const dayOfWeek = date.getDay() // 0~6

                    // 使用本地時區格式化日期，避免時區轉換問題
                    const year = date.getFullYear()
                    const month = String(date.getMonth() + 1).padStart(2, '0')
                    const day = String(date.getDate()).padStart(2, '0')
                    const ymd = `${year}-${month}-${day}`

                    // 1. 先檢查公休日：每週固定公休或特殊公休日
                    const isClosedDay = !weekly[dayOfWeek] || special.includes(ymd)

                    // 2. 檢查已有訂位資料：該日是否客滿
                    const isFullyBooked = availabilityData.unavailable_dates.includes(ymd)

                    // 符合任一條件即排除
                    if (isClosedDay || isFullyBooked) {
                        disableDates.push(new Date(date))
                    }
                }

                console.log('zhTw:', zhTw)
                // 使用標準的中文繁體 locale
                const localeOption = zhTw.zh_tw || zhTw.default || zhTw
                console.log('flatpickr localeOption:', localeOption)

                this.datePicker = flatpickr(this.dateTarget, {
                    locale: localeOption,
                    inline: false, // 改為點擊才顯示
                    position: 'auto center', // 置中顯示
                    static: false, // 允許動態定位
                    appendTo: document.body, // 附加到 body 以避免容器限制
                    minDate: 'today',
                    maxDate: new Date().fp_incr(this.maxReservationDays),
                    disable: disableDates,
                    onChange: (selectedDates) => {
                        if (selectedDates && selectedDates.length > 0) {
                            // 使用本地時區格式化日期，避免時區轉換問題
                            const selectedDate = selectedDates[0]
                            const year = selectedDate.getFullYear()
                            const month = String(selectedDate.getMonth() + 1).padStart(2, '0')
                            const day = String(selectedDate.getDate()).padStart(2, '0')
                            this.selectedDate = `${year}-${month}-${day}`

                            console.log('選擇的日期 (本地時區):', this.selectedDate)

                            // 更新隱藏欄位
                            const dateField = document.querySelector('input[name="date"], #reservation_date')
                            if (dateField) {
                                dateField.value = this.selectedDate
                            }

                            this.loadAllTimeSlots(this.selectedDate)

                            // 重置已選擇的餐期和時間
                            this.selectedPeriodId = null
                            this.selectedTime = null
                            this.updateFormState()
                        }
                    },
                })

                console.log('🔥 Flatpickr initialized successfully:', this.datePicker)
                console.log('🔥 Flatpickr calendar element:', this.datePicker.calendarContainer)
                console.log('🔥 dateTarget after flatpickr:', this.dateTarget)
                console.log('🔥 dateTarget parent:', this.dateTarget.parentElement)
            } else {
                console.error('🔥 dateTarget not available for flatpickr initialization')
            }

            // 初始化日期選擇器後，設置默認日期為第一個可用日期
            const availableDates = []
            const today2 = new Date()
            const endDate2 = new Date()
            endDate2.setDate(today2.getDate() + this.maxReservationDays)

            for (let date = new Date(today2); date <= endDate2; date.setDate(date.getDate() + 1)) {
                const dayOfWeek = date.getDay()

                // 使用本地時區格式化日期，避免時區轉換問題
                const year = date.getFullYear()
                const month = String(date.getMonth() + 1).padStart(2, '0')
                const day = String(date.getDate()).padStart(2, '0')
                const ymd = `${year}-${month}-${day}`

                // 1. 檢查不是公休日（週間固定公休或特殊公休日）
                const isOpenDay = weekly[dayOfWeek] && !special.includes(ymd)

                // 2. 檢查有可用訂位（該日非客滿）
                const hasAvailability = !availabilityData.unavailable_dates.includes(ymd)

                // 兩個條件都滿足才是可用日期
                if (isOpenDay && hasAvailability) {
                    availableDates.push(new Date(date))
                }
            }

            if (availableDates.length > 0) {
                console.log('找到可用日期，設置為默認日期:', availableDates[0])

                // 設置日期選擇器的默認日期
                this.datePicker.setDate(availableDates[0])

                // 手動設置選擇的日期
                const selectedDate = availableDates[0]
                const year = selectedDate.getFullYear()
                const month = String(selectedDate.getMonth() + 1).padStart(2, '0')
                const day = String(selectedDate.getDate()).padStart(2, '0')
                this.selectedDate = `${year}-${month}-${day}`

                // 更新隱藏欄位
                const dateField = document.querySelector('input[name="date"], #reservation_date')
                if (dateField) {
                    dateField.value = this.selectedDate
                }

                // 手動加載該日期的時間槽
                this.loadAllTimeSlots(this.selectedDate)

                console.log('🔥 已自動加載日期的時間槽:', this.selectedDate)
            } else {
                console.log('🔥 沒有找到可用日期')
            }
        } catch (error) {
            console.error('🔥 初始化日期選擇器時出錯:', error)
            console.error('🔥 Error stack:', error.stack)
            if (this.hasTimeSlotsTarget) {
                this.timeSlotsTarget.innerHTML = '<div class="text-red-500 p-4 text-center">無法載入可用日期</div>'
            }
        }
    }

    // 加載所有時間槽 (調整為當前專案的 API 端點)
    async loadAllTimeSlots(date) {
        const adultCount = this.hasAdultCountTarget ? this.adultCountTarget.value : 2
        const childCount = this.hasChildCountTarget ? this.childCountTarget.value : 0

        if (!this.hasTimeSlotsTarget) {
            console.error('缺少 timeSlots 目標元素')
            return
        }

        // 清空時間容器
        this.timeSlotsTarget.innerHTML = '<p class="text-gray-400 w-full">載入中...</p>'

        if (this.hasPeriodInfoTarget) {
            this.periodInfoTarget.innerHTML = ''
        }

        try {
            // 載入按餐期分類的時間槽 (調整為當前專案的 API 端點)
            const response = await fetch(
                `/restaurants/${this.restaurantSlugValue}/reservations/available_slots?date=${date}&adult_count=${adultCount}&child_count=${childCount}`
            )
            const data = await response.json()

            // 清空時間容器
            this.timeSlotsTarget.innerHTML = ''

            // 檢查是否有可用時間
            const slots = data.slots

            if (!slots || slots.length === 0) {
                if (this.hasPeriodInfoTarget) {
                    this.periodInfoTarget.innerHTML = '<span class="text-yellow-500">該日無可用餐期</span>'
                }
                this.timeSlotsTarget.innerHTML = '<p class="text-yellow-500 w-full">該日無可用時間</p>'
                return
            }

            // 按餐期名稱分類時間槽
            const periodSlots = {}

            // 將時間槽按餐期分類
            slots.forEach((slot) => {
                const periodName = slot.period_name
                if (!periodSlots[periodName]) {
                    periodSlots[periodName] = []
                }
                periodSlots[periodName].push(slot)
            })

            // 顯示餐期信息
            const periodNames = Object.keys(periodSlots)
            if (periodNames.length > 0 && this.hasPeriodInfoTarget) {
                this.periodInfoTarget.innerHTML = `<span>可用餐期: ${periodNames.join(', ')}</span>`
            }

            // 為每個餐期創建一個區塊
            Object.keys(periodSlots).forEach((periodName) => {
                const slotsInPeriod = periodSlots[periodName]

                // 創建餐期區塊
                const periodDiv = document.createElement('div')
                periodDiv.className = 'mb-4'

                // 添加標題
                const heading = document.createElement('h3')
                heading.className = 'flex items-center font-semibold text-gray-800 mb-4 text-lg'

                // 添加圖標
                const icon = document.createElement('span')
                icon.className = 'inline-block w-2 h-2 bg-blue-500 rounded-full mr-3'

                heading.appendChild(icon)
                heading.appendChild(document.createTextNode(periodName))
                periodDiv.appendChild(heading)

                // 創建時間選項容器
                const timeContainer = document.createElement('div')
                timeContainer.className = 'grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-4'

                // 添加時間選項
                slotsInPeriod.forEach((slot) => {
                    const timeElement = document.createElement('button')
                    timeElement.type = 'button'
                    timeElement.className =
                        'time-option group relative px-6 py-4 rounded-xl border-2 border-gray-200 bg-white text-gray-700 font-medium transition-all duration-300 ease-in-out transform hover:scale-105 hover:shadow-lg hover:border-blue-300 hover:bg-blue-50 focus:outline-none focus:ring-4 focus:ring-blue-100 focus:border-blue-400'

                    // 創建時間顯示
                    const timeSpan = document.createElement('span')
                    timeSpan.className = 'block text-lg font-semibold'
                    timeSpan.textContent = slot.time

                    // 創建可用性指示器
                    const indicator = document.createElement('div')
                    indicator.className =
                        'absolute top-2 right-2 w-3 h-3 bg-green-400 rounded-full opacity-80 group-hover:opacity-100 transition-opacity'

                    // 創建底部標籤
                    const label = document.createElement('span')
                    label.className = 'block text-xs text-gray-500 mt-1 group-hover:text-blue-600 transition-colors'
                    label.textContent = '可預約'

                    timeElement.appendChild(indicator)
                    timeElement.appendChild(timeSpan)
                    timeElement.appendChild(label)

                    // 儲存該時間對應的餐期ID和餐期名稱
                    timeElement.dataset.periodId = slot.period_id
                    timeElement.dataset.periodName = slot.period_name

                    // 點擊事件
                    timeElement.addEventListener('click', (event) => this.selectTimeSlot(event))

                    timeContainer.appendChild(timeElement)
                })

                periodDiv.appendChild(timeContainer)
                this.timeSlotsTarget.appendChild(periodDiv)
            })
        } catch (error) {
            console.error('無法載入時間:', error)
            if (this.hasPeriodInfoTarget) {
                this.periodInfoTarget.innerHTML = '<span class="text-red-500">無法載入餐期</span>'
            }
            this.timeSlotsTarget.innerHTML = '<p class="text-red-500 w-full">無法載入時間</p>'
        }
    }

    // 選擇時間槽
    selectTimeSlot(event) {
        // 移除所有選中樣式
        this.element.querySelectorAll('.time-option').forEach((el) => {
            el.classList.remove('selected')
            // 重置為未選中狀態
            el.className =
                'time-option group relative px-6 py-4 rounded-xl border-2 border-gray-200 bg-white text-gray-700 font-medium transition-all duration-300 ease-in-out transform hover:scale-105 hover:shadow-lg hover:border-blue-300 hover:bg-blue-50 focus:outline-none focus:ring-4 focus:ring-blue-100 focus:border-blue-400'

            // 重置內部元素樣式
            const timeSpan = el.querySelector('span:first-of-type')
            const label = el.querySelector('span:last-of-type')
            const indicator = el.querySelector('div')

            if (timeSpan) {
                timeSpan.className = 'block text-lg font-semibold'
            }
            if (label) {
                label.className = 'block text-xs text-gray-500 mt-1 group-hover:text-blue-600 transition-colors'
                label.textContent = '可預約'
            }
            if (indicator) {
                indicator.className =
                    'absolute top-2 right-2 w-3 h-3 bg-green-400 rounded-full opacity-80 group-hover:opacity-100 transition-opacity'
            }
        })

        // 添加選中樣式
        const selectedElement = event.currentTarget
        selectedElement.classList.add('selected')
        selectedElement.className =
            'time-option selected relative px-6 py-4 rounded-xl border-2 border-blue-500 bg-gradient-to-r from-blue-500 to-blue-600 text-white font-medium transition-all duration-300 ease-in-out transform scale-105 shadow-xl ring-4 ring-blue-200'

        // 更新內部元素樣式
        const timeSpan = selectedElement.querySelector('span:first-of-type')
        const label = selectedElement.querySelector('span:last-of-type')
        const indicator = selectedElement.querySelector('div')

        if (timeSpan) {
            timeSpan.className = 'block text-lg font-bold text-white'
        }
        if (label) {
            label.className = 'block text-xs text-blue-100 mt-1'
            label.textContent = '已選擇'
        }
        if (indicator) {
            indicator.className = 'absolute top-2 right-2 w-3 h-3 bg-white rounded-full shadow-sm'
        }

        // 更新狀態
        this.selectedTime = selectedElement.querySelector('span:first-of-type').textContent
        this.selectedPeriodId = selectedElement.dataset.periodId

        console.log('選擇時間槽:', this.selectedTime, '餐期ID:', this.selectedPeriodId)

        // 更新表單狀態
        this.updateFormState()
    }

    // 更新表單狀態
    updateFormState() {
        // 查找所有隱藏欄位
        const dateField = document.querySelector('input[name="date"], #reservation_date')
        const timeField = document.querySelector('input[name="time"], #reservation_time')
        const periodIdField = document.querySelector('input[name="period_id"], #operating_period_id')
        const adultCountField = document.querySelector(
            'select[name="reservation[adult_count]"], [data-reservation-target="adultCount"]'
        )
        const childCountField = document.querySelector(
            'select[name="reservation[child_count]"], [data-reservation-target="childCount"]'
        )

        // 更新隱藏欄位值
        if (dateField && this.selectedDate) {
            dateField.value = this.selectedDate
        }

        if (timeField && this.selectedTime) {
            timeField.value = this.selectedTime
        }

        if (periodIdField && this.selectedPeriodId) {
            periodIdField.value = this.selectedPeriodId
        }

        // 取得表單
        const form = this.element.closest('form') || document.getElementById('reservation-form')

        if (this.selectedDate && this.selectedTime && this.selectedPeriodId && form) {
            // 啟用下一步按鈕
            if (this.hasNextStepTarget) {
                this.nextStepTarget.disabled = false
            }

            // 確保人數欄位也有值
            const adultCount = adultCountField ? adultCountField.value : 2
            const childCount = childCountField ? childCountField.value : 0

            // 檢查是否有隱藏欄位存儲人數
            const adultHiddenField = form.querySelector('input[name="adults"]')
            const childHiddenField = form.querySelector('input[name="children"]')

            // 如果沒有隱藏欄位，就創建
            if (!adultHiddenField && adultCount) {
                const adultHidden = document.createElement('input')
                adultHidden.type = 'hidden'
                adultHidden.name = 'adults'
                adultHidden.value = adultCount
                form.appendChild(adultHidden)
            } else if (adultHiddenField) {
                adultHiddenField.value = adultCount
            }

            if (!childHiddenField && childCount) {
                const childHidden = document.createElement('input')
                childHidden.type = 'hidden'
                childHidden.name = 'children'
                childHidden.value = childCount
                form.appendChild(childHidden)
            } else if (childHiddenField) {
                childHiddenField.value = childCount
            }

            // 同時添加 URL 參數欄位，確保它們也能被提交
            // 為日期添加額外的 URL 參數
            let dateParamField = form.querySelector('input[name="date"]')
            if (!dateParamField) {
                dateParamField = document.createElement('input')
                dateParamField.type = 'hidden'
                dateParamField.name = 'date'
                form.appendChild(dateParamField)
            }
            dateParamField.value = this.selectedDate

            // 為時間添加額外的 URL 參數
            let timeParamField = form.querySelector('input[name="time"]')
            if (!timeParamField) {
                timeParamField = document.createElement('input')
                timeParamField.type = 'hidden'
                timeParamField.name = 'time'
                form.appendChild(timeParamField)
            }
            timeParamField.value = this.selectedTime

            // 為餐期ID添加額外的 URL 參數
            let periodParamField = form.querySelector('input[name="period_id"]')
            if (!periodParamField) {
                periodParamField = document.createElement('input')
                periodParamField.type = 'hidden'
                periodParamField.name = 'period_id'
                form.appendChild(periodParamField)
            }
            periodParamField.value = this.selectedPeriodId

            // 調試信息
            console.log('表單已更新:', {
                date: dateField ? dateField.value : '未找到日期欄位',
                time: timeField ? timeField.value : '未找到時間欄位',
                periodId: periodIdField ? periodIdField.value : '未找到餐期欄位',
                adultCount: adultCount,
                childCount: childCount,
                dateParam: dateParamField.value,
                timeParam: timeParamField.value,
                periodParam: periodParamField.value,
            })
        } else {
            // 禁用下一步按鈕
            if (this.hasNextStepTarget) {
                this.nextStepTarget.disabled = true
            }
        }
    }
}
