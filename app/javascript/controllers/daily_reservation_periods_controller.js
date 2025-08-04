import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]

  connect() {
    console.log("Daily reservation periods controller connected")
  }

  toggleDay(event) {
    const weekday = event.target.dataset.weekday
    const isChecked = event.target.checked
    const row = event.target.closest('.daily-period-row')
    const statusDisplay = row.querySelector('.status-display')
    
    if (isChecked) {
      // 啟用該日，顯示編輯按鈕
      statusDisplay.innerHTML = '<span class="text-gray-500">點擊編輯設定營業時段</span>'
      row.classList.remove('opacity-50')
    } else {
      // 停用該日
      statusDisplay.innerHTML = '<span class="text-gray-500">不開放訂位</span>'
      row.classList.add('opacity-50')
      // 這裡可以發送 AJAX 請求停用該日的營業時段
      this.disableDay(weekday)
    }
  }

  editDay(event) {
    const weekday = event.target.dataset.weekday
    this.openEditModal(weekday)
  }

  copyDay(event) {
    const weekday = event.target.dataset.weekday
    // 實現複製功能
    console.log(`Copy day ${weekday}`)
  }

  async openEditModal(weekday) {
    try {
      const response = await fetch(`/admin/restaurants/${this.getRestaurantSlug()}/reservation_periods/edit_day?weekday=${weekday}`, {
        headers: {
          'Accept': 'text/html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const html = await response.text()
        const modalContainer = document.getElementById('edit-modal-container')
        const modalContent = document.getElementById('edit-modal-content')
        
        modalContent.innerHTML = html
        modalContainer.classList.remove('hidden')
        
        // 觸發 modal 顯示動畫
        setTimeout(() => {
          modalContainer.classList.add('opacity-100')
        }, 10)
      }
    } catch (error) {
      console.error('Error opening edit modal:', error)
    }
  }

  async disableDay(weekday) {
    try {
      await fetch(`/admin/restaurants/${this.getRestaurantSlug()}/reservation_periods/disable_day`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken(),
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: JSON.stringify({ weekday: weekday })
      })
    } catch (error) {
      console.error('Error disabling day:', error)
    }
  }

  getRestaurantSlug() {
    return window.location.pathname.split('/')[3] // 假設路徑是 /admin/restaurants/:slug/...
  }

  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
  }
}