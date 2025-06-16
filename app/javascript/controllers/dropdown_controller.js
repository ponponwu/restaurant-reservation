import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = ['button', 'menu']

    connect() {
        this.boundClickOutside = this.clickOutside.bind(this)
    }

    disconnect() {
        document.removeEventListener('click', this.boundClickOutside)
    }

    toggle(event) {
        event.preventDefault()
        event.stopPropagation()

        if (this.menuTarget.classList.contains('hidden')) {
            this.open()
        } else {
            this.close()
        }
    }

    open() {
        this.menuTarget.classList.remove('hidden')
        document.addEventListener('click', this.boundClickOutside)
    }

    close() {
        this.menuTarget.classList.add('hidden')
        document.removeEventListener('click', this.boundClickOutside)
    }

    clickOutside(event) {
        if (!this.element.contains(event.target)) {
            this.close()
        }
    }
}
