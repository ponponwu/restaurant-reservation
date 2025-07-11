import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = [
        'customHoursSection',
        'periods',
        'periodsContainer',
        'period'
    ]

    static identifier = 'special-date-form'

    connect() {
        console.log('SpecialDateForm controller connected')
        this.periodIndex = this.periodTargets.length
    }

    // 切換營業模式時顯示/隱藏自訂時段區塊
    toggleMode(event) {
        const operationMode = event.target.value
        const customHoursSection = this.customHoursSectionTarget
        
        if (operationMode === 'custom_hours') {
            customHoursSection.classList.remove('hidden')
        } else {
            customHoursSection.classList.add('hidden')
        }
    }

    // 新增時段
    addPeriod(event) {
        event.preventDefault()
        
        const newPeriodHTML = this.generatePeriodHTML(this.periodIndex)
        this.periodsTarget.insertAdjacentHTML('beforeend', newPeriodHTML)
        this.periodIndex++
    }

    // 移除時段
    removePeriod(event) {
        event.preventDefault()
        
        const periodElement = event.target.closest('[data-special-date-form-target="period"]')
        
        // 確保至少保留一個時段
        if (this.periodTargets.length > 1) {
            periodElement.remove()
        } else {
            alert('至少需要保留一個營業時段')
        }
    }

    // 生成時段 HTML
    generatePeriodHTML(index) {
        return `
            <div class="flex items-center space-x-3 mb-3 p-3 border border-gray-200 rounded-lg bg-gray-50" 
                 data-special-date-form-target="period">
                <div class="flex-1 grid grid-cols-3 gap-3">
                    <div>
                        <label class="block text-xs font-medium text-gray-600 mb-1">開始時間</label>
                        <input type="time" 
                               name="special_reservation_date[custom_periods][${index}][start_time]" 
                               value="18:00"
                               class="block w-full text-sm border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500">
                    </div>
                    
                    <div>
                        <label class="block text-xs font-medium text-gray-600 mb-1">結束時間</label>
                        <input type="time" 
                               name="special_reservation_date[custom_periods][${index}][end_time]" 
                               value="21:00"
                               class="block w-full text-sm border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500">
                    </div>
                    
                    <div>
                        <label class="block text-xs font-medium text-gray-600 mb-1">間隔 (分鐘)</label>
                        <select name="special_reservation_date[custom_periods][${index}][interval_minutes]" 
                                class="block w-full text-sm border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500">
                            <option value="30">30分鐘</option>
                            <option value="60">60分鐘</option>
                            <option value="90">90分鐘</option>
                            <option value="120" selected>120分鐘</option>
                            <option value="180">180分鐘</option>
                        </select>
                    </div>
                </div>
                
                <button type="button" 
                        data-action="click->special-date-form#removePeriod"
                        class="flex-shrink-0 p-2 text-red-600 hover:text-red-800"
                        title="移除此時段">
                    <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
                    </svg>
                </button>
            </div>
        `
    }

    // 表單驗證
    validateForm(event) {
        const form = event.target
        const operationMode = form.querySelector('select[name="special_reservation_date[operation_mode]"]').value
        const startDate = form.querySelector('input[name="special_reservation_date[start_date]"]').value
        const endDate = form.querySelector('input[name="special_reservation_date[end_date]"]').value
        
        // 基本驗證
        if (!startDate || !endDate) {
            alert('請設定開始和結束日期')
            event.preventDefault()
            return false
        }
        
        if (new Date(startDate) > new Date(endDate)) {
            alert('結束日期不能早於開始日期')
            event.preventDefault()
            return false
        }
        
        // 自訂時段驗證
        if (operationMode === 'custom_hours') {
            const periods = this.periodTargets
            let hasValidPeriod = false
            
            periods.forEach(period => {
                const startTimeInput = period.querySelector('input[name*="[start_time]"]')
                const endTimeInput = period.querySelector('input[name*="[end_time]"]')

                if (startTimeInput && endTimeInput) {
                    const startTime = startTimeInput.value
                    const endTime = endTimeInput.value

                    if (startTime && endTime && startTime < endTime) {
                        hasValidPeriod = true
                    }
                }
            })
            
            if (!hasValidPeriod) {
                alert('自訂時段模式下，至少需要設定一個有效的營業時段')
                event.preventDefault()
                return false
            }
        }
        
        return true
    }
}