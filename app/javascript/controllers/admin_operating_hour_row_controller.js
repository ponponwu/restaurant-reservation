import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
  static values = { editMode: Boolean }

  connect() {
    console.log('Admin Operating Hour Row controller connected')
    console.log('Edit mode:', this.editModeValue)
    
    // 如果是編輯模式，自動聚焦到第一個時間輸入框
    if (this.editModeValue) {
      this.focusFirstTimeInput()
    }
  }

  // 進入編輯模式
  enterEditMode(event) {
    event.preventDefault()
    console.log('Entering edit mode')
    
    // 觸發 Turbo 請求來獲取編輯表單
    // 這將重新渲染這個 turbo_frame 為編輯模式
    const operatingHourId = this.getOperatingHourId()
    if (operatingHourId) {
      const editUrl = `/admin/restaurants/${this.getRestaurantId()}/operating_hours/${operatingHourId}/edit`
      Turbo.visit(editUrl, { frame: this.getFrameId() })
    }
  }

  // 取消編輯
  cancelEdit(event) {
    event.preventDefault()
    console.log('Canceling edit')
    
    const operatingHourId = this.getOperatingHourId()
    if (operatingHourId) {
      // 重新載入顯示模式
      const showUrl = `/admin/restaurants/${this.getRestaurantId()}/operating_hours/${operatingHourId}`
      Turbo.visit(showUrl, { frame: this.getFrameId() })
    } else {
      // 如果是新的記錄，直接移除
      this.element.remove()
    }
  }

  // 處理表單提交
  handleFormSubmit(event) {
    console.log('Handling form submit')
    // Turbo 會自動處理表單提交和回應
  }

  // 私有方法：聚焦到第一個時間輸入框
  focusFirstTimeInput() {
    const firstTimeInput = this.element.querySelector('input[type="time"]')
    if (firstTimeInput) {
      setTimeout(() => {
        firstTimeInput.focus()
      }, 100)
    }
  }

  // 私有方法：獲取營業時間 ID
  getOperatingHourId() {
    const frameElement = this.element.closest('turbo-frame')
    if (frameElement && frameElement.id.startsWith('operating_hour_')) {
      const match = frameElement.id.match(/operating_hour_(\d+)/)
      return match ? match[1] : null
    }
    return null
  }

  // 私有方法：獲取餐廳 ID (從 URL 或 data 屬性)
  getRestaurantId() {
    // 嘗試從 URL 路徑中提取餐廳 slug
    const pathMatch = window.location.pathname.match(/\/restaurants\/([^\/]+)/)
    return pathMatch ? pathMatch[1] : null
  }

  // 私有方法：獲取 frame ID
  getFrameId() {
    const frameElement = this.element.closest('turbo-frame')
    return frameElement ? frameElement.id : null
  }
}