import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["spinner"]

  submit() {
    this.showSpinner()
    this.element.requestSubmit()
  }

  showSpinner() {
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("hidden")
    }
  }

  hideSpinner() {
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.add("hidden")
    }
  }

  connect() {
    // 監聽 turbo:submit-end 事件來隱藏載入指示器
    this.element.addEventListener('turbo:submit-end', () => {
      this.hideSpinner()
    })
  }
}
