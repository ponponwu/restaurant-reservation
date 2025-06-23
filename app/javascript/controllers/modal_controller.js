import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = ['overlay', 'content', 'title', 'message', 'confirmBtn', 'icon', 'iconContainer']

    connect() {
        this.pendingForm = null
        this.pendingAction = null

        // 註冊全域 flash 顯示函數
        window.showModalFlash = (message, type) => {
            this.showFlash(message, type)
        }

        // 添加全域事件委派來處理動態載入的關閉按鈕
        this.boundHandleModalClose = this.handleModalClose.bind(this)
        document.addEventListener('click', this.boundHandleModalClose)
    }

    disconnect() {
        // 清理事件監聽器
        if (this.boundHandleModalClose) {
            document.removeEventListener('click', this.boundHandleModalClose)
        }
    }

    // 處理 modal 關閉按鈕的全域點擊事件
    handleModalClose(event) {
        // 檢查點擊的元素是否有 modal 關閉 action
        const closestActionElement = event.target.closest('[data-action*="modal#close"]')
        if (closestActionElement) {
            event.preventDefault()
            this.close()
        }
    }

    // 顯示確認對話框
    show(event) {
        event.preventDefault()

        const button = event.currentTarget
        const form = button.closest('form')
        const title = button.dataset.confirmTitle || '確認操作'
        const message = button.dataset.confirmMessage || '您確定要執行此操作嗎？'
        const confirmText = button.dataset.confirmText || '確認'
        const type = button.dataset.confirmType || 'danger' // danger, warning, info

        // 尋找 modal 元素（可能在不同的 DOM 區域）
        const modal = document.getElementById('confirmation-modal')
        const titleElement = modal?.querySelector('[data-modal-target="title"]')
        const messageElement = modal?.querySelector('[data-modal-target="message"]')
        const confirmBtnElement = modal?.querySelector('[data-modal-target="confirmBtn"]')
        const overlayElement = modal?.querySelector('[data-modal-target="overlay"]')
        const contentElement = modal?.querySelector('[data-modal-target="content"]')

        if (!modal || !titleElement || !messageElement || !confirmBtnElement) {
            console.error('❌ Modal elements not found')
            return
        }

        // 設定 modal 內容
        titleElement.textContent = title
        messageElement.textContent = message
        confirmBtnElement.textContent = confirmText

        // 設定圖示和顏色
        this.setModalStyleForElement(modal, type)

        // 儲存待執行的表單或動作
        this.pendingForm = form
        this.pendingAction = () => {
            if (form) {
                form.submit()
            } else {
                // 如果沒有表單，執行其他動作（例如連結點擊）
                const href = button.href
                if (href) {
                    window.location.href = href
                }
            }
        }

        // 顯示 modal
        modal.classList.remove('hidden')
        modal.classList.add('flex')

        // 加入動畫效果
        requestAnimationFrame(() => {
            overlayElement?.classList.add('opacity-100')
            contentElement?.classList.add('opacity-100', 'translate-y-0', 'sm:scale-100')
        })
    }

    // 關閉對話框
    close() {
        // 嘗試關閉確認對話框
        const confirmationModal = document.getElementById('confirmation-modal')
        if (confirmationModal && !confirmationModal.classList.contains('hidden')) {
            const overlayElement = confirmationModal?.querySelector('[data-modal-target="overlay"]')
            const contentElement = confirmationModal?.querySelector('[data-modal-target="content"]')

            if (overlayElement && contentElement) {
                overlayElement.classList.remove('opacity-100')
                contentElement.classList.remove('opacity-100', 'translate-y-0', 'sm:scale-100')
            }

            setTimeout(() => {
                if (confirmationModal) {
                    confirmationModal.classList.add('hidden')
                    confirmationModal.classList.remove('flex')
                }
                this.pendingForm = null
                this.pendingAction = null
            }, 200)
            return
        }

        // 嘗試關閉內容 modal
        const modalContainer = document.getElementById('modal-container')
        if (modalContainer && !modalContainer.classList.contains('hidden')) {
            modalContainer.classList.add('hidden')

            // 清空內容
            const modalContent = document.getElementById('modal-content')
            if (modalContent) {
                modalContent.innerHTML = ''
            }
        }
    }

    // 確認操作
    confirm() {
        if (this.pendingAction) {
            // 先執行動作
            this.pendingAction()

            // 然後關閉 modal
            this.close()
        } else {
            this.close()
        }
    }

    // 設定 modal 的樣式（圖示和顏色）- 使用元素參數
    setModalStyleForElement(modal, type) {
        const iconContainer = modal.querySelector('[data-modal-target="iconContainer"]')
        const icon = modal.querySelector('[data-modal-target="icon"]')
        const confirmBtn = modal.querySelector('[data-modal-target="confirmBtn"]')

        if (!iconContainer || !icon || !confirmBtn) {
            console.error('❌ Modal style elements not found')
            return
        }

        this.applyModalStyle(iconContainer, icon, confirmBtn, type)
    }

    // 設定 modal 的樣式（圖示和顏色）- 原始方法
    setModalStyle(type) {
        const iconContainer = this.iconContainerTarget
        const icon = this.iconTarget
        const confirmBtn = this.confirmBtnTarget

        this.applyModalStyle(iconContainer, icon, confirmBtn, type)
    }

    // 通用的樣式套用方法
    applyModalStyle(iconContainer, icon, confirmBtn, type) {
        // 重置所有樣式
        iconContainer.className =
            'mx-auto flex-shrink-0 flex items-center justify-center h-12 w-12 rounded-full sm:mx-0 sm:h-10 sm:w-10'
        confirmBtn.className =
            'w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 text-base font-medium text-white focus:outline-none focus:ring-2 focus:ring-offset-2 sm:ml-3 sm:w-auto sm:text-sm'

        switch (type) {
            case 'danger':
                iconContainer.classList.add('bg-red-100')
                icon.classList.add('text-red-600')
                confirmBtn.classList.add('bg-red-600', 'hover:bg-red-700', 'focus:ring-red-500')
                // 警告圖示
                icon.innerHTML =
                    '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />'
                break
            case 'warning':
                iconContainer.classList.add('bg-yellow-100')
                icon.classList.add('text-yellow-600')
                confirmBtn.classList.add('bg-yellow-600', 'hover:bg-yellow-700', 'focus:ring-yellow-500')
                // 驚嘆號圖示
                icon.innerHTML =
                    '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />'
                break
            case 'info':
                iconContainer.classList.add('bg-blue-100')
                icon.classList.add('text-blue-600')
                confirmBtn.classList.add('bg-blue-600', 'hover:bg-blue-700', 'focus:ring-blue-500')
                // 資訊圖示
                icon.innerHTML =
                    '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />'
                break
            default:
                iconContainer.classList.add('bg-gray-100')
                icon.classList.add('text-gray-600')
                confirmBtn.classList.add('bg-gray-600', 'hover:bg-gray-700', 'focus:ring-gray-500')
        }
    }

    // 鍵盤事件處理
    keydown(event) {
        if (event.key === 'Escape') {
            this.close()
        } else if (event.key === 'Enter') {
            this.confirm()
        }
    }

    // 顯示 flash 訊息
    showFlash(message, type = 'success') {
        const flashContainer = document.getElementById('modal-flash-messages')
        const flashContent = document.getElementById('modal-flash-content')
        const flashIcon = document.getElementById('modal-flash-icon')
        const flashText = document.getElementById('modal-flash-text')

        if (!flashContainer || !flashContent || !flashIcon || !flashText) return

        // 清除之前的樣式
        flashContent.className = 'rounded-md p-4'
        flashIcon.innerHTML = ''

        // 根據類型設定樣式和圖示
        switch (type) {
            case 'success':
                flashContent.classList.add('bg-green-50', 'border', 'border-green-200')
                flashIcon.classList.add('text-green-400')
                flashIcon.innerHTML =
                    '<path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"></path>'
                flashText.classList.add('text-green-800')
                break
            case 'error':
                flashContent.classList.add('bg-red-50', 'border', 'border-red-200')
                flashIcon.classList.add('text-red-400')
                flashIcon.innerHTML =
                    '<path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path>'
                flashText.classList.add('text-red-800')
                break
            case 'warning':
                flashContent.classList.add('bg-yellow-50', 'border', 'border-yellow-200')
                flashIcon.classList.add('text-yellow-400')
                flashIcon.innerHTML =
                    '<path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>'
                flashText.classList.add('text-yellow-800')
                break
        }

        // 設定訊息文字
        flashText.textContent = message

        // 顯示訊息
        flashContainer.classList.remove('hidden')

        // 3 秒後自動隱藏
        setTimeout(() => {
            flashContainer.classList.add('hidden')
        }, 3000)
    }

    // 隱藏 flash 訊息
    hideFlash() {
        const flashContainer = document.getElementById('modal-flash-messages')
        if (flashContainer) {
            flashContainer.classList.add('hidden')
        }
    }

    testClick() {
        alert('Stimulus modal controller 工作正常！')
    }

    // 遠程載入 Modal 內容
    openRemote(event) {
        event.preventDefault()

        const link = event.currentTarget
        const url = link.href

        // 找到 modal 容器
        const modalContainer = document.getElementById('modal-container')
        const modalContent = document.getElementById('modal-content')

        if (!modalContainer || !modalContent) {
            console.error('❌ Modal container not found')
            return
        }

        // 顯示載入狀態
        modalContent.innerHTML = `
            <div class="p-6 text-center">
                <svg class="animate-spin h-8 w-8 text-gray-400 mx-auto" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 0 1 8-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 0 1 4 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                <p class="mt-2 text-gray-500">載入中...</p>
            </div>
        `

        // 顯示 Modal
        modalContainer.classList.remove('hidden')

        // 透過 AJAX 載入內容
        fetch(url, {
            headers: {
                Accept: 'text/html',
                'X-Requested-With': 'XMLHttpRequest',
            },
        })
            .then((response) => {
                console.log('📡 Response status:', response.status)
                console.log('📡 Response headers:', response.headers.get('Content-Type'))

                if (!response.ok) {
                    throw new Error(`HTTP ${response.status}: ${response.statusText}`)
                }
                return response.text()
            })
            .then((html) => {
                console.log('✅ HTML loaded successfully, length:', html.length)
                modalContent.innerHTML = html

                // 移除有問題的 application.load() 調用
                // 動態內容中的關閉按鈕會由全域事件委派處理
            })
            .catch((error) => {
                console.error('💥 載入失敗詳細錯誤:', error)
                modalContent.innerHTML = `
                <div class="p-6 text-center">
                    <p class="text-red-500">載入失敗：${error.message}</p>
                    <p class="text-sm text-gray-500 mt-2">請檢查控制台了解詳細錯誤</p>
                </div>
            `
            })
    }
}
