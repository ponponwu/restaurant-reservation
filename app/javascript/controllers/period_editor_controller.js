import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["customPeriodsSection", "periodsList"]

  connect() {
    console.log("Period editor controller connected")
    this.updateAllPreviews()
  }

  modeChanged(event) {
    const mode = event.target.value
    const customSection = document.getElementById('custom-periods-section')
    
    if (mode === 'custom_hours') {
      customSection.classList.remove('hidden')
    } else {
      customSection.classList.add('hidden')
    }
  }

  timeChanged(event) {
    const periodItem = event.target.closest('.period-item')
    this.updatePreview(periodItem)
  }

  intervalChanged(event) {
    const periodItem = event.target.closest('.period-item')
    this.updatePreview(periodItem)
  }

  addPeriod(event) {
    const periodsContainer = document.getElementById('periods-list')
    const existingPeriods = periodsContainer.querySelectorAll('.period-item')
    const newIndex = existingPeriods.length
    
    const newPeriodHTML = this.createPeriodHTML(newIndex)
    periodsContainer.insertAdjacentHTML('beforeend', newPeriodHTML)
    
    // 更新新時段的預覽
    const newPeriod = periodsContainer.lastElementChild
    this.updatePreview(newPeriod)
  }

  removePeriod(event) {
    const periodItem = event.target.closest('.period-item')
    periodItem.remove()
    this.reindexPeriods()
  }

  async savePeriods(event) {
    const weekday = event.target.dataset.weekday
    const mode = document.querySelector('input[name="operation_mode"]:checked').value
    const periods = this.collectPeriods()
    
    try {
      const response = await fetch(`/admin/restaurants/${this.getRestaurantSlug()}/reservation_periods/update_day`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken(),
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: JSON.stringify({
          weekday: weekday,
          operation_mode: mode,
          periods: periods
        })
      })
      
      if (response.ok) {
        // 關閉 modal
        this.closeModal()
        // 刷新頁面內容
        window.location.reload()
      } else {
        console.error('Error saving periods')
      }
    } catch (error) {
      console.error('Error saving periods:', error)
    }
  }

  updatePreview(periodItem) {
    const startTime = periodItem.querySelector('input[name$="[start_time]"]').value
    const endTime = periodItem.querySelector('input[name$="[end_time]"]').value
    const interval = parseInt(periodItem.querySelector('select[name$="[interval]"]').value)
    
    if (startTime && endTime && interval) {
      const slots = this.generateTimeSlots(startTime, endTime, interval)
      const slotCount = periodItem.querySelector('.slot-count')
      const slotsPreview = periodItem.querySelector('.time-slots-preview')
      
      if (slotCount) slotCount.textContent = slots.length
      if (slotsPreview) slotsPreview.textContent = slots.join(', ')
    }
  }

  updateAllPreviews() {
    const periods = document.querySelectorAll('.period-item')
    periods.forEach(period => this.updatePreview(period))
  }

  generateTimeSlots(startTime, endTime, intervalMinutes) {
    const slots = []
    const start = new Date(`2000-01-01T${startTime}:00`)
    const end = new Date(`2000-01-01T${endTime}:00`)
    
    let current = new Date(start)
    
    while (current <= end) {
      slots.push(current.toTimeString().slice(0, 5))
      current.setMinutes(current.getMinutes() + intervalMinutes)
    }
    
    return slots
  }

  createPeriodHTML(index) {
    return `
      <div class="period-item bg-gray-50 p-4 rounded-lg" data-period-index="${index}">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div class="md:col-span-2">
            <div class="flex items-center space-x-2">
              <input type="time" 
                     name="periods[${index}][start_time]" 
                     value="18:00"
                     class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                     data-action="change->period-editor#timeChanged" />
              <span class="text-gray-500">至</span>
              <input type="time" 
                     name="periods[${index}][end_time]" 
                     value="20:00"
                     class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                     data-action="change->period-editor#timeChanged" />
            </div>
          </div>
          <div>
            <select name="periods[${index}][interval]" 
                    class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                    data-action="change->period-editor#intervalChanged">
              <option value="15">15 分鐘</option>
              <option value="30" selected>30 分鐘</option>
              <option value="60">60 分鐘</option>
              <option value="90">90 分鐘</option>
              <option value="120">120 分鐘</option>
              <option value="150">150 分鐘</option>
              <option value="180">180 分鐘</option>
              <option value="210">210 分鐘</option>
              <option value="240">240 分鐘</option>
            </select>
          </div>
        </div>
        <div class="mt-3">
          <div class="text-sm text-gray-600">
            訂位時間選項：共 <span class="slot-count">5</span> 個
          </div>
          <div class="time-slots-preview mt-1 text-sm text-gray-500">
            18:00, 18:30, 19:00, 19:30, 20:00
          </div>
        </div>
        <div class="mt-3 flex justify-end">
          <button type="button" 
                  class="text-red-600 hover:text-red-800 text-sm"
                  data-action="click->period-editor#removePeriod"
                  data-period-index="${index}">
            移除此時段
          </button>
        </div>
      </div>
    `
  }

  collectPeriods() {
    const periods = []
    const periodItems = document.querySelectorAll('.period-item')
    
    periodItems.forEach(item => {
      const startTime = item.querySelector('input[name$="[start_time]"]').value
      const endTime = item.querySelector('input[name$="[end_time]"]').value
      const interval = item.querySelector('select[name$="[interval]"]').value
      
      if (startTime && endTime) {
        periods.push({
          start_time: startTime,
          end_time: endTime,
          interval_minutes: parseInt(interval)
        })
      }
    })
    
    return periods
  }

  reindexPeriods() {
    const periodItems = document.querySelectorAll('.period-item')
    periodItems.forEach((item, index) => {
      item.dataset.periodIndex = index
      item.querySelector('input[name$="[start_time]"]').name = `periods[${index}][start_time]`
      item.querySelector('input[name$="[end_time]"]').name = `periods[${index}][end_time]`
      item.querySelector('select[name$="[interval]"]').name = `periods[${index}][interval]`
      
      const removeButton = item.querySelector('button[data-action*="removePeriod"]')
      if (removeButton) {
        removeButton.dataset.periodIndex = index
      }
    })
  }

  closeModal() {
    const modalContainer = document.getElementById('edit-modal-container')
    modalContainer.classList.add('hidden')
  }

  getRestaurantSlug() {
    return window.location.pathname.split('/')[3]
  }

  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
  }
}