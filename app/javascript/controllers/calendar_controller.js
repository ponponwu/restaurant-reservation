import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = ['monthYear', 'daysGrid', 'selectedDate']
    static values = { currentUrl: String }

    static classes = ['selected', 'today', 'normal']

    connect() {
        console.log('Calendar controller connected')
        console.log('Available targets:', {
            monthYear: this.hasMonthYearTarget,
            daysGrid: this.hasDaysGridTarget,
            selectedDate: this.hasSelectedDateTarget,
        })

        this.currentDate = new Date()
        this.selectedDateValue = new Date()
        this.monthNames = [
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
        ]

        // 等待 DOM 完全載入後渲染
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => this.initializeCalendar())
        } else {
            this.initializeCalendar()
        }
    }

    initializeCalendar() {
        try {
            this.renderCalendar()
            this.updateSelectedDateDisplay()
        } catch (error) {
            console.error('Failed to initialize calendar:', error)
        }
    }

    previousMonth() {
        this.currentDate.setMonth(this.currentDate.getMonth() - 1)
        this.renderCalendar()
    }

    nextMonth() {
        this.currentDate.setMonth(this.currentDate.getMonth() + 1)
        this.renderCalendar()
    }

    selectDate(event) {
        const dateButton = event.target.closest('[data-date]')
        if (!dateButton) return

        const dateString = dateButton.dataset.date
        this.selectedDateValue = new Date(dateString)

        // 移除之前選中的樣式
        this.daysGridTarget.querySelectorAll('.bg-blue-500').forEach((el) => {
            el.classList.remove('bg-blue-500', 'text-white')
            el.classList.add('hover:bg-gray-100')
        })

        // 添加新的選中樣式
        dateButton.classList.remove('hover:bg-gray-100')
        dateButton.classList.add('bg-blue-500', 'text-white')

        this.updateSelectedDateDisplay()
        this.filterReservationsByDate(dateString)
    }

    renderCalendar() {
        console.log('Rendering calendar...')
        const year = this.currentDate.getFullYear()
        const month = this.currentDate.getMonth()

        // 檢查必要的 targets 是否存在
        if (!this.monthYearTarget || !this.daysGridTarget) {
            console.error('Calendar targets not found:', {
                monthYear: this.monthYearTarget,
                daysGrid: this.daysGridTarget,
            })
            return
        }

        // 更新月份年份顯示
        this.monthYearTarget.textContent = `${year}年 ${this.monthNames[month]}`

        // 清空日期網格
        this.daysGridTarget.innerHTML = ''

        // 獲取本月第一天和最後一天
        const firstDay = new Date(year, month, 1)
        const lastDay = new Date(year, month + 1, 0)
        const firstDayOfWeek = firstDay.getDay()

        console.log('Calendar info:', { year, month, firstDayOfWeek, lastDay: lastDay.getDate() })

        // 添加上個月的空白天數
        for (let i = 0; i < firstDayOfWeek; i++) {
            const emptyDay = document.createElement('div')
            emptyDay.className = 'h-8'
            this.daysGridTarget.appendChild(emptyDay)
        }

        // 添加本月的日期
        for (let day = 1; day <= lastDay.getDate(); day++) {
            const dayButton = this.createDayButton(year, month, day)
            this.daysGridTarget.appendChild(dayButton)
        }

        console.log('Calendar rendered with', this.daysGridTarget.children.length, 'elements')
    }

    createDayButton(year, month, day) {
        const date = new Date(year, month, day)
        const dateString = this.formatDateForServer(date)
        const today = new Date()
        const isToday = this.isSameDate(date, today)
        const isSelected = this.isSameDate(date, this.selectedDateValue)

        const button = document.createElement('button')
        button.type = 'button'
        button.textContent = day
        button.dataset.date = dateString
        button.dataset.action = 'click->calendar#selectDate'

        let classes = 'h-8 w-8 text-sm rounded-full transition-colors duration-200 '

        if (isSelected) {
            classes += 'bg-blue-500 text-white'
        } else if (isToday) {
            classes += 'bg-blue-100 text-blue-600 font-medium hover:bg-blue-200'
        } else {
            classes += 'text-gray-700 hover:bg-gray-100'
        }

        button.className = classes

        return button
    }

    isSameDate(date1, date2) {
        return (
            date1.getFullYear() === date2.getFullYear() &&
            date1.getMonth() === date2.getMonth() &&
            date1.getDate() === date2.getDate()
        )
    }

    formatDateForServer(date) {
        const year = date.getFullYear()
        const month = String(date.getMonth() + 1).padStart(2, '0')
        const day = String(date.getDate()).padStart(2, '0')
        return `${year}-${month}-${day}`
    }

    formatDateForDisplay(date) {
        const year = date.getFullYear()
        const month = date.getMonth() + 1
        const day = date.getDate()
        return `${year}年${month}月${day}日`
    }

    updateSelectedDateDisplay() {
        this.selectedDateTarget.textContent = this.formatDateForDisplay(this.selectedDateValue)
    }

    async filterReservationsByDate(dateString) {
        try {
            // 顯示載入狀態
            this.showLoading()

            // 構建請求 URL
            const url = new URL(this.currentUrlValue, window.location.origin)
            url.searchParams.set('date_filter', dateString)

            // 發送請求
            const response = await fetch(url, {
                headers: {
                    Accept: 'text/vnd.turbo-stream.html',
                    'X-Requested-With': 'XMLHttpRequest',
                },
            })

            if (response.ok) {
                const html = await response.text()
                Turbo.renderStreamMessage(html)
            } else {
                console.error('Failed to filter reservations:', response.statusText)
            }
        } catch (error) {
            console.error('Error filtering reservations:', error)
        } finally {
            this.hideLoading()
        }
    }

    showLoading() {
        // 可以添加載入指示器
        const reservationList = document.querySelector('.reservation-list')
        if (reservationList) {
            reservationList.style.opacity = '0.6'
        }
    }

    hideLoading() {
        const reservationList = document.querySelector('.reservation-list')
        if (reservationList) {
            reservationList.style.opacity = '1'
        }
    }
}
