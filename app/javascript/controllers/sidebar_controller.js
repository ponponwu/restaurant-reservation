import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = ['sidebar', 'overlay', 'mainContainer']

    connect() {
        this.setupEventListeners()
    }

    setupEventListeners() {
        window.addEventListener('resize', this.handleResize.bind(this))
        document.addEventListener('keydown', this.handleKeydown.bind(this))
    }

    toggle() {
        if (this.isMobile()) {
            if (this.sidebarTarget.classList.contains('sidebar-open')) {
                this.close()
            } else {
                this.show()
            }
        }
    }

    show() {
        if (this.isMobile()) {
            this.sidebarTarget.classList.add('sidebar-open')

            if (this.hasOverlayTarget) {
                this.overlayTarget.style.display = 'block'
                this.overlayTarget.offsetHeight
                this.overlayTarget.classList.add('opacity-75')
            }

            document.body.classList.add('overflow-hidden')

            if (this.hasMainContainerTarget) {
                this.mainContainerTarget.style.transition = 'transform 0.3s ease-in-out'
                this.mainContainerTarget.style.transform = 'translateX(18rem)' // 18rem is w-72
            }
        }
    }

    close() {
        if (this.isMobile()) {
            this.sidebarTarget.classList.remove('sidebar-open')

            if (this.hasOverlayTarget) {
                this.overlayTarget.classList.remove('opacity-75')
                setTimeout(() => {
                    this.overlayTarget.style.display = 'none'
                }, 300)
            }

            document.body.classList.remove('overflow-hidden')

            if (this.hasMainContainerTarget) {
                this.mainContainerTarget.style.transform = ''
            }
        }
    }

    handleResize() {
        if (!this.isMobile()) {
            this.close()
            // Ensure main container is reset on resize to desktop
            if (this.hasMainContainerTarget) {
                this.mainContainerTarget.style.transform = ''
                this.mainContainerTarget.style.transition = ''
            }
        }
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.close()
        }
    }

    isMobile() {
        return window.innerWidth < 1024 // lg breakpoint
    }

    disconnect() {
        window.removeEventListener('resize', this.handleResize.bind(this))
        document.removeEventListener('keydown', this.handleKeydown.bind(this))
        document.body.classList.remove('overflow-hidden')
    }
}
