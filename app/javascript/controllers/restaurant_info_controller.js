import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = ['infoButton', 'infoPanel']

    connect() {
        console.log('🔥 Restaurant Info Controller connected')
    }

    toggleInfo() {
        console.log('🔥 Toggle restaurant info')

        if (this.infoPanelTarget.classList.contains('hidden')) {
            // 顯示資訊面板
            this.infoPanelTarget.classList.remove('hidden')
            this.infoPanelTarget.classList.add('animate-slideDown')
        } else {
            // 隱藏資訊面板
            this.infoPanelTarget.classList.add('hidden')
            this.infoPanelTarget.classList.remove('animate-slideDown')
        }
    }
}
