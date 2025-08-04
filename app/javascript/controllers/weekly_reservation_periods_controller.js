import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    restaurantSlug: String
  }

  connect() {
    console.log("Weekly Business Periods Controller connected")
  }

  editDay(event) {
    const weekday = event.currentTarget.dataset.weekday
    const url = `/admin/restaurant_settings/restaurants/${this.restaurantSlugValue}/weekly_day/${weekday}/edit`
    
    this.loadModal(url)
  }

  copyDay(event) {
    const sourceWeekday = event.currentTarget.dataset.weekday
    
    // 顯示複製選項對話框
    this.showCopyDialog(sourceWeekday)
  }

  showCopyDialog(sourceWeekday) {
    const targetOptions = [
      { value: 0, label: '星期日' },
      { value: 1, label: '星期一' },
      { value: 2, label: '星期二' },
      { value: 3, label: '星期三' },
      { value: 4, label: '星期四' },
      { value: 5, label: '星期五' },
      { value: 6, label: '星期六' }
    ].filter(option => option.value != sourceWeekday)

    const checkboxes = targetOptions.map(option => 
      `<label class="flex items-center">
        <input type="checkbox" name="target_weekdays" value="${option.value}" class="mr-2">
        ${option.label}
      </label>`
    ).join('')

    const content = `
      <div class="p-6">
        <h3 class="text-lg font-medium mb-4">複製營業時段到其他星期</h3>
        <div class="space-y-2 mb-6">
          ${checkboxes}
        </div>
        <div class="flex justify-end space-x-3">
          <button type="button" class="px-4 py-2 border border-gray-300 rounded text-sm" onclick="this.closest('.modal').style.display='none'">取消</button>
          <button type="button" class="px-4 py-2 bg-blue-600 text-white rounded text-sm" onclick="this.submitCopy(${sourceWeekday})">複製</button>
        </div>
      </div>
    `

    this.showModal(content)
  }

  submitCopy(sourceWeekday) {
    const selectedTargets = document.querySelectorAll('input[name="target_weekdays"]:checked')
    
    if (selectedTargets.length === 0) {
      alert('請選擇要複製到的星期')
      return
    }

    const form = document.createElement('form')
    form.method = 'POST'
    form.action = `/admin/restaurant_settings/restaurants/${this.restaurantSlugValue}/weekly_day/copy`
    
    const csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content')
    form.innerHTML = `
      <input type="hidden" name="authenticity_token" value="${csrfToken}">
      <input type="hidden" name="source_weekday" value="${sourceWeekday}">
    `

    selectedTargets.forEach(checkbox => {
      const input = document.createElement('input')
      input.type = 'hidden'
      input.name = 'target_weekdays[]'
      input.value = checkbox.value
      form.appendChild(input)
    })

    // 關閉複製模態框
    this.closeModal()
    
    document.body.appendChild(form)
    form.submit()
  }

  loadModal(url) {
    fetch(url, {
      headers: {
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'text/html'
      }
    })
    .then(response => response.text())
    .then(html => {
      this.showModal(html)
    })
    .catch(error => {
      console.error('Error loading modal:', error)
    })
  }

  showModal(content) {
    const modalContainer = document.getElementById('weekly-modal-container')
    const modalContent = document.getElementById('weekly-modal-content')
    
    modalContent.innerHTML = content
    modalContainer.classList.remove('hidden')
    
    // 確保 PeriodEditorController 已註冊
    if (window.Stimulus && !window.Stimulus.router.modules.find(m => m.identifier === 'period-editor')) {
      window.Stimulus.register("period-editor", PeriodEditorController)
    }
    
    // 手動連接期間編輯器控制器
    const periodEditorElement = modalContent.querySelector('[data-controller*="period-editor"]')
    if (periodEditorElement && window.Stimulus) {
      window.Stimulus.application.start()
    }
  }

  closeModal() {
    const modalContainer = document.getElementById('weekly-modal-container')
    modalContainer.classList.add('hidden')
  }

  saveWeeklyPeriods(event) {
    const weekday = event.target.dataset.weekday
    const operationMode = document.querySelector('input[name="operation_mode"]:checked').value
    
    const form = document.createElement('form')
    form.method = 'POST'
    form.action = `/admin/restaurant_settings/restaurants/${this.restaurantSlugValue}/weekly_day/${weekday}`
    
    const csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content')
    
    // Add hidden method field for PATCH
    form.innerHTML = `
      <input type="hidden" name="_method" value="patch">
      <input type="hidden" name="authenticity_token" value="${csrfToken}">
      <input type="hidden" name="operation_mode" value="${operationMode}">
    `

    if (operationMode === 'custom_hours') {
      const periods = document.querySelectorAll('.period-item')
      periods.forEach((period, index) => {
        const startTime = period.querySelector('input[type="time"]:first-of-type').value
        const endTime = period.querySelector('input[type="time"]:last-of-type').value
        const interval = period.querySelector('select').value
        
        form.innerHTML += `
          <input type="hidden" name="periods[${index}][start_time]" value="${startTime}">
          <input type="hidden" name="periods[${index}][end_time]" value="${endTime}">
          <input type="hidden" name="periods[${index}][interval]" value="${interval}">
        `
      })
    }

    document.body.appendChild(form)
    form.submit()
  }
}

// 期間編輯器控制器
class PeriodEditorController extends Controller {
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
    this.updateTimeSlots(event.target.closest('.period-item'))
  }

  intervalChanged(event) {
    this.updateTimeSlots(event.target.closest('.period-item'))
  }

  updateTimeSlots(periodItem) {
    const startTime = periodItem.querySelector('input[type="time"]:first-of-type').value
    const endTime = periodItem.querySelector('input[type="time"]:last-of-type').value
    const interval = parseInt(periodItem.querySelector('select').value)
    
    if (startTime && endTime && interval) {
      const slots = this.generateTimeSlots(startTime, endTime, interval)
      const slotCount = periodItem.querySelector('.slot-count')
      const slotPreview = periodItem.querySelector('.time-slots-preview')
      
      slotCount.textContent = slots.length
      slotPreview.textContent = slots.join(', ')
    }
  }

  generateTimeSlots(startTime, endTime, intervalMinutes) {
    const slots = []
    const start = new Date(`2000-01-01T${startTime}:00`)
    const end = new Date(`2000-01-01T${endTime}:00`)
    
    let current = new Date(start)
    while (current < end) {
      slots.push(current.toLocaleTimeString('zh-TW', { hour: '2-digit', minute: '2-digit', hour12: false }))
      current.setMinutes(current.getMinutes() + intervalMinutes)
    }
    
    return slots
  }

  addPeriod() {
    const periodsList = document.getElementById('periods-list')
    const newIndex = periodsList.children.length
    
    const newPeriod = document.createElement('div')
    newPeriod.className = 'period-item bg-gray-50 p-4 rounded-lg'
    newPeriod.dataset.periodIndex = newIndex
    newPeriod.innerHTML = `
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="md:col-span-2">
          <div class="flex items-center space-x-2">
            <input type="time" name="periods[${newIndex}][start_time]" value="18:00" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm" data-action="change->period-editor#timeChanged" />
            <span class="text-gray-500">至</span>
            <input type="time" name="periods[${newIndex}][end_time]" value="20:00" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm" data-action="change->period-editor#timeChanged" />
          </div>
        </div>
        <div>
          <select name="periods[${newIndex}][interval]" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm" data-action="change->period-editor#intervalChanged">
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
        <div class="text-sm text-gray-600">訂位時間選項：共 <span class="slot-count">5</span> 個</div>
        <div class="time-slots-preview mt-1 text-sm text-gray-500">18:00, 18:30, 19:00, 19:30, 20:00</div>
      </div>
      <div class="mt-3 flex justify-end">
        <button type="button" class="text-red-600 hover:text-red-800 text-sm" data-action="click->period-editor#removePeriod" data-period-index="${newIndex}">移除此時段</button>
      </div>
    `
    
    periodsList.appendChild(newPeriod)
    this.updateTimeSlots(newPeriod)
  }

  removePeriod(event) {
    const periodItem = event.target.closest('.period-item')
    periodItem.remove()
  }
}

// 註冊期間編輯器控制器
if (window.Stimulus) {
  window.Stimulus.register("period-editor", PeriodEditorController)
}