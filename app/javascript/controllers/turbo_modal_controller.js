import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = ['container', 'frame']

    connect() {
        this.boundFrameLoad = this.frameLoad.bind(this)
        this.boundFrameBeforeLoad = this.frameBeforeLoad.bind(this)

        // 監聽 turbo-frame 的載入事件
        if (this.hasFrameTarget) {
            this.frameTarget.addEventListener('turbo:frame-load', this.boundFrameLoad)
            this.frameTarget.addEventListener('turbo:before-frame-render', this.boundFrameBeforeLoad)
        }
    }

    disconnect() {
        if (this.hasFrameTarget && this.boundFrameLoad) {
            this.frameTarget.removeEventListener('turbo:frame-load', this.boundFrameLoad)
            this.frameTarget.removeEventListener('turbo:before-frame-render', this.boundFrameBeforeLoad)
        }
    }

    frameBeforeLoad(event) {
        // 在載入前顯示 loading 狀態
        this.showLoading()
    }

    frameLoad(event) {
        // 當 frame 載入內容時
        if (this.frameTarget.innerHTML.trim()) {
            this.show()
        } else {
            this.hide()
        }
    }

    show() {
        if (this.hasContainerTarget) {
            this.containerTarget.classList.remove('hidden')
            // 添加動畫效果
            requestAnimationFrame(() => {
                this.containerTarget.classList.add('opacity-100')
            })
        }
    }

    hide() {
        if (this.hasContainerTarget) {
            this.containerTarget.classList.add('hidden')
            this.containerTarget.classList.remove('opacity-100')
        }
    }

    close() {
        // 清空 frame 內容並隱藏 modal
        if (this.hasFrameTarget) {
            this.frameTarget.innerHTML = ''
        }
        this.hide()
    }

    showLoading() {
        if (this.hasFrameTarget) {
            this.frameTarget.innerHTML = `
        <div class="px-4 pt-5 pb-4 sm:p-6">
          <div class="text-center">
            <svg class="animate-spin h-8 w-8 text-gray-400 mx-auto" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 0 1 8-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 0 1 4 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            <p class="mt-2 text-gray-500">載入中...</p>
          </div>
        </div>
      `
        }
        this.show()
    }

    // 監聽鍵盤事件
    keydown(event) {
        if (event.key === 'Escape') {
            this.close()
        }
    }

    // 處理背景點擊
    backgroundClick(event) {
        if (event.target === event.currentTarget) {
            this.close()
        }
    }
}
