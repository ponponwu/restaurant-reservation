import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = ['infoButton', 'infoPanel', 'reminderButton', 'reminderPanel']

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

    toggleReminder() {
        console.log('🔥 Toggle reminder info')

        if (this.hasReminderPanelTarget) {
            if (this.reminderPanelTarget.classList.contains('hidden')) {
                // 顯示提醒事項面板
                this.reminderPanelTarget.classList.remove('hidden')
                this.reminderPanelTarget.classList.add('animate-slideDown')
            } else {
                // 隱藏提醒事項面板
                this.reminderPanelTarget.classList.add('hidden')
                this.reminderPanelTarget.classList.remove('animate-slideDown')
            }
        }
    }
}
