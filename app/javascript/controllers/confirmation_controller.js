import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static values = { message: String }

    connect() {
        this.element.addEventListener('click', this.handleClick.bind(this))
    }

    handleClick(event) {
        const message = this.messageValue || '確定要執行此操作嗎？'

        if (!confirm(message)) {
            event.preventDefault()
            event.stopPropagation()
            return false
        }
    }
}
