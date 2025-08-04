import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
  static targets = ['timeDisplay', 'editForm']

  connect() {
    console.log('Operating Hour Row controller connected')
  }

  // 顯示編輯表單
  showForm() {
    const timeDisplay = this.element.querySelector('.text-gray-700')
    const editForm = this.element.querySelector('form')
    
    if (timeDisplay && editForm) {
      timeDisplay.classList.add('hidden')
      editForm.classList.remove('hidden')
      editForm.classList.add('flex')
      
      // 聚焦到第一個時間輸入框
      const firstTimeInput = editForm.querySelector('input[type="time"]')
      if (firstTimeInput) {
        firstTimeInput.focus()
      }
    }
  }

  // 取消編輯
  cancel() {
    const timeDisplay = this.element.querySelector('.text-gray-700')
    const editForm = this.element.querySelector('form')
    
    if (timeDisplay && editForm) {
      timeDisplay.classList.remove('hidden')
      editForm.classList.add('hidden')
      editForm.classList.remove('flex')
    }
  }

  // 表單提交成功後的處理
  formSuccess() {
    // Turbo Stream 會自動處理更新，這裡不需要做任何事
    console.log('Form submitted successfully')
  }
}