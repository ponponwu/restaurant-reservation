import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
  connect() {
    console.log('Admin Operating Hours controller connected')
  }

  // 新增營業時間 (通用)
  addNew(event) {
    console.log('Adding new operating hour')
    // 表單會自動提交，Turbo Stream 會處理回應
  }

  // 新增特定星期的營業時間
  addNewForWeekday(event) {
    const weekday = event.currentTarget.dataset.weekday
    console.log(`Adding new operating hour for weekday: ${weekday}`)
    // 表單會自動提交，Turbo Stream 會處理回應
  }
}