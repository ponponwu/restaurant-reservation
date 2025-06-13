import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = ['modal', 'tabContent', 'tab']
    static values = {
        restaurantSlug: String,
        currentTab: String,
    }
    static classes = ['activeTab', 'inactiveTab', 'loading']

    connect() {
        console.log('🔗 Restaurant management controller connected')
        console.log('🎯 Modal target:', this.modalTarget)
        console.log('🏪 Restaurant slug:', this.restaurantSlugValue)

        // 設定全域函數以便動態載入的內容使用
        this.setupGlobalFunctions()
    }

    // 設定全域函數
    setupGlobalFunctions() {
        // 公休日期相關的全域函數
        window.openModal = (modalId) => {
            this.openModalById(modalId)
        }

        window.closeModal = (modalId) => {
            this.closeModal(modalId)
        }

        window.setWeeklyClosureModal = () => {
            this.openModalById('weeklyClosureModal')
        }

        window.setHolidayClosureModal = () => {
            this.openModalById('holidayClosureModal')
        }

        window.createHolidayClosures = () => {
            this.createHolidayClosures()
        }
    }

    // 開啟管理模態視窗
    openModal() {
        console.log('🔓 Opening modal - button clicked')
        console.log('🎯 Modal element:', this.modalTarget)

        if (this.modalTarget) {
            console.log('📋 Modal classes before:', this.modalTarget.classList.toString())
            this.modalTarget.classList.remove('hidden')
            console.log('📋 Modal classes after:', this.modalTarget.classList.toString())

            // 自動顯示第一個標籤頁（餐廳資訊）
            setTimeout(() => {
                this.activateFirstTab()
            }, 100)
        } else {
            console.error('❌ Modal target not found!')
        }
    }

    // 啟用第一個標籤頁
    activateFirstTab() {
        // 找到第一個標籤頁按鈕並模擬點擊
        const firstTabButton = this.tabTargets[0]
        if (firstTabButton) {
            const event = {
                target: firstTabButton,
                params: { tab: 'restaurant-info' },
            }
            this.switchTab(event)
        }
    }

    // 關閉管理模態視窗
    closeMainModal() {
        console.log('🔒 Closing main modal')
        if (this.modalTarget) {
            console.log('✅ Modal target found, adding hidden class')
            this.modalTarget.classList.add('hidden')
            console.log('✅ Main modal closed successfully')
        } else {
            console.error('❌ Modal target not found!')
        }
    }

    // 點擊背景關閉模態視窗
    closeOnBackground(event) {
        console.log('🖱️ Background clicked')
        console.log('🎯 Event target:', event.target)
        console.log('🎯 Modal target:', this.modalTarget)

        // 只有當點擊的是模態視窗背景本身時才關閉
        if (event.target === this.modalTarget) {
            console.log('✅ Closing modal from background click')
            this.closeMainModal()
        } else {
            console.log('⚠️ Not closing - clicked on modal content')
        }
    }

    // 切換標籤頁
    switchTab(event) {
        const tabName = event.params.tab

        // 隱藏所有選項卡內容
        this.tabContentTargets.forEach((tab) => {
            tab.classList.add('hidden')
        })

        // 重置所有選項卡樣式
        this.tabTargets.forEach((tab) => {
            tab.classList.remove('border-blue-500', 'text-blue-600')
            tab.classList.add('border-transparent', 'text-gray-500')
        })

        // 顯示選中的選項卡
        const targetTab = document.getElementById(`${tabName}-tab`)
        if (targetTab) {
            targetTab.classList.remove('hidden')

            // 更新選項卡樣式
            const clickedTab = event.target.closest('button')
            if (clickedTab) {
                clickedTab.classList.remove('border-transparent', 'text-gray-500')
                clickedTab.classList.add('border-blue-500', 'text-blue-600')
            }

            // 載入對應內容
            this.loadTabContent(tabName)
        }

        this.currentTabValue = tabName
    }

    // 載入選項卡內容
    async loadTabContent(tabName) {
        const contentDiv = document.getElementById(`${tabName}-content`)
        if (!contentDiv) return

        // 顯示載入狀態
        this.showLoading(contentDiv)

        try {
            const url = this.getTabUrl(tabName)
            console.log('🌐 Loading tab:', tabName, 'URL:', url)

            const response = await fetch(url, {
                headers: {
                    Accept: 'text/html, application/xhtml+xml',
                    'X-Requested-With': 'XMLHttpRequest',
                    'Content-Type': 'application/html',
                },
            })

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`)
            }

            const html = await response.text()
            console.log('📄 Received HTML length:', html.length)

            const parser = new DOMParser()
            const doc = parser.parseFromString(html, 'text/html')

            const extractedContent = this.extractContent(doc, tabName)

            if (extractedContent) {
                console.log('✅ Extracted content successfully')
                contentDiv.innerHTML = extractedContent.innerHTML

                // 重新初始化事件
                this.initializeTabScripts(tabName, contentDiv)

                // 重新初始化 Stimulus 控制器
                this.reinitializeStimulusControllers(contentDiv)
            } else {
                this.showError(contentDiv, '載入失敗，請稍後再試')
            }
        } catch (error) {
            console.error('💥 載入失敗:', error)
            this.showError(contentDiv, '載入失敗，請稍後再試')
        }
    }

    // 獲取選項卡對應的 URL
    getTabUrl(tabName) {
        const slug = this.restaurantSlugValue

        switch (tabName) {
            case 'restaurant-info':
                return `/admin/restaurants/${slug}/edit`
            case 'business-periods':
                return `/admin/restaurants/${slug}/business_periods`
            case 'closure-dates':
                return `/admin/restaurant_settings/restaurants/${slug}/closure_dates`
            default:
                return null
        }
    }

    // 提取頁面內容
    extractContent(doc, tabName) {
        console.log('🔍 Extracting content for tab:', tabName)

        let mainContent

        if (tabName === 'restaurant-info') {
            // 餐廳資訊：提取表單內容
            mainContent = doc.querySelector('form') || doc.querySelector('.max-w-7xl')
            console.log('📋 Restaurant info form found:', !!mainContent)
        } else if (tabName === 'business-periods') {
            // 營業時段：提取主要內容但移除頁面標題和返回按鈕
            const container = doc.querySelector('.max-w-7xl')
            console.log('🕐 Business periods container found:', !!container)

            if (container) {
                mainContent = container.cloneNode(true)

                // 移除頁面標題區塊
                const titleSection = mainContent.querySelector('.mb-8')
                if (titleSection && titleSection.querySelector('h1')) {
                    console.log('🗑️ Removing title section')
                    titleSection.remove()
                }

                // 移除返回按鈕
                const backLinks = mainContent.querySelectorAll('a[href*="admin_restaurant"]')
                console.log('🔗 Back links found:', backLinks.length)
                backLinks.forEach((link) => {
                    if (link.textContent.includes('返回')) {
                        console.log('🗑️ Removing back link')
                        link.closest('.flex')?.remove()
                    }
                })
            }
        } else if (tabName === 'closure-dates') {
            // 公休日期：提取主要內容但移除頁面標題、導覽和返回按鈕
            const container = doc.querySelector('.max-w-7xl')
            console.log('📅 Closure dates container found:', !!container)

            if (container) {
                mainContent = container.cloneNode(true)

                // 確保保留 data-controller 和相關屬性
                if (!mainContent.dataset.controller) {
                    const originalController = container.querySelector('[data-controller*="closure-dates"]')
                    if (originalController) {
                        console.log('🔧 Preserving closure-dates controller attributes')
                        mainContent.setAttribute('data-controller', originalController.dataset.controller)
                        // 複製所有 data-closure-dates 相關屬性
                        Object.keys(originalController.dataset).forEach((key) => {
                            if (key.startsWith('closureDates')) {
                                mainContent.dataset[key] = originalController.dataset[key]
                                console.log(`📋 Copied ${key}:`, originalController.dataset[key])
                            }
                        })
                    }
                }

                // 移除頁面標題區塊
                const titleSection = mainContent.querySelector('.mb-8')
                if (titleSection && titleSection.querySelector('h1')) {
                    console.log('🗑️ Removing title section')
                    titleSection.remove()
                }

                // 移除選項卡導覽
                const tabsNav = mainContent.querySelector('.border-b.border-gray-200')
                if (tabsNav && tabsNav.querySelector('nav')) {
                    console.log('🗑️ Removing tabs navigation')
                    tabsNav.remove()
                }

                // 移除返回按鈕
                const backLinks = mainContent.querySelectorAll('a[href*="admin_restaurant_settings"]')
                console.log('🔗 Back links found:', backLinks.length)
                backLinks.forEach((link) => {
                    if (link.textContent.includes('返回')) {
                        console.log('🗑️ Removing back link')
                        link.closest('.flex')?.remove()
                    }
                })
            }
        }

        console.log('📦 Extracted content:', !!mainContent)
        if (mainContent) {
            console.log('📏 Content HTML length:', mainContent.innerHTML.length)
        }

        return mainContent
    }

    // 初始化選項卡腳本
    initializeTabScripts(tabName, contentDiv) {
        if (tabName === 'business-periods') {
            this.initializeBusinessPeriods(contentDiv)
        } else if (tabName === 'closure-dates') {
            this.initializeClosureDates(contentDiv)
        }

        // 通用表單處理
        this.initializeForms(contentDiv, tabName)
    }

    // 初始化營業時段功能
    initializeBusinessPeriods(contentDiv) {
        console.log('🕐 Initializing business periods functionality')

        // 重新綁定編輯按鈕
        const editButtons = contentDiv.querySelectorAll('a[href*="edit"], button[data-action*="edit"]')
        editButtons.forEach((button) => {
            button.addEventListener('click', (e) => {
                e.preventDefault()
                const url = button.href || button.dataset.url
                if (url) {
                    this.loadEditContent(url)
                }
            })
        })

        // 重新綁定切換狀態按鈕
        const toggleButtons = contentDiv.querySelectorAll('button[data-action*="toggle"]')
        toggleButtons.forEach((button) => {
            button.addEventListener('click', async (e) => {
                e.preventDefault()
                const url = button.dataset.url
                if (url) {
                    try {
                        const response = await fetch(url, {
                            method: 'PATCH',
                            headers: {
                                'X-CSRF-Token': this.getCSRFToken(),
                                Accept: 'text/vnd.turbo-stream.html',
                            },
                        })

                        if (response.ok) {
                            // 重新載入營業時段內容
                            this.loadTabContent('business-periods')
                        }
                    } catch (error) {
                        console.error('💥 切換狀態失敗:', error)
                        alert('操作失敗，請稍後再試')
                    }
                }
            })
        })

        // 重新綁定新增營業時段表單
        const newBusinessPeriodForm = contentDiv.querySelector('#new_business_period_form form')
        if (newBusinessPeriodForm) {
            newBusinessPeriodForm.addEventListener('submit', async (e) => {
                e.preventDefault()

                try {
                    const formData = new FormData(newBusinessPeriodForm)
                    const response = await fetch(newBusinessPeriodForm.action, {
                        method: 'POST',
                        body: formData,
                        headers: {
                            'X-CSRF-Token': this.getCSRFToken(),
                            Accept: 'text/vnd.turbo-stream.html',
                        },
                    })

                    if (response.ok) {
                        // 重新載入營業時段內容
                        this.loadTabContent('business-periods')
                    } else {
                        throw new Error('提交失敗')
                    }
                } catch (error) {
                    console.error('💥 新增營業時段失敗:', error)
                    alert('新增失敗，請稍後再試')
                }
            })
        }
    }

    // 初始化公休日期功能
    initializeClosureDates(contentDiv) {
        console.log('📅 Initializing closure dates functionality')

        // 定義全域備用函數，以防頁面中的腳本沒有載入
        if (!window.handleWeeklyClosureSubmit) {
            console.log('🔧 Defining backup handleWeeklyClosureSubmit function')
            window.handleWeeklyClosureSubmit = async (event) => {
                console.log('🔥 Backup handleWeeklyClosureSubmit called!')
                event.preventDefault()

                const container = event.target.closest('[data-controller*="closure-dates"]')
                if (container) {
                    await this.manualWeeklySubmit(container)
                } else {
                    console.error('❌ Could not find closure dates container for backup handler')
                    alert('找不到公休日期控制器')
                }
            }
        }

        // 重新綁定編輯和刪除按鈕
        const editButtons = contentDiv.querySelectorAll('button[onclick*="edit"], a[href*="edit"]')
        editButtons.forEach((button) => {
            button.addEventListener('click', (e) => {
                e.preventDefault()
                const url = button.href || button.dataset.url
                if (url) {
                    this.loadEditContent(url)
                }
            })
        })

        // 重新綁定刪除按鈕
        const deleteButtons = contentDiv.querySelectorAll('form[method="post"] button[title="刪除"]')
        deleteButtons.forEach((button) => {
            const form = button.closest('form')
            if (form) {
                form.addEventListener('submit', async (e) => {
                    e.preventDefault()

                    const confirmMessage = button.dataset.confirm || '確定要刪除嗎？'
                    if (confirm(confirmMessage)) {
                        try {
                            const formData = new FormData(form)
                            const response = await fetch(form.action, {
                                method: 'DELETE',
                                body: formData,
                                headers: {
                                    'X-CSRF-Token': this.getCSRFToken(),
                                    Accept: 'text/vnd.turbo-stream.html',
                                    'X-Requested-With': 'XMLHttpRequest',
                                },
                            })

                            if (response.ok) {
                                console.log('✅ Delete successful')

                                // 如果回應是 Turbo Stream，處理它
                                const responseText = await response.text()
                                console.log('📡 Response received, content type:', response.headers.get('Content-Type'))

                                if (response.headers.get('Content-Type')?.includes('turbo-stream')) {
                                    console.log('📡 Processing Turbo Stream response')
                                    // 讓 Turbo 處理回應
                                    const turboStreamElement = document.createElement('div')
                                    turboStreamElement.innerHTML = responseText

                                    // 執行每個 turbo-stream 動作
                                    const turboStreams = turboStreamElement.querySelectorAll('turbo-stream')
                                    console.log(`🔄 Found ${turboStreams.length} turbo-stream elements`)

                                    turboStreams.forEach((stream, index) => {
                                        const action = stream.getAttribute('action')
                                        const target = stream.getAttribute('target')
                                        const template = stream.querySelector('template')

                                        console.log(
                                            `📋 Processing stream ${index + 1}: action=${action}, target=${target}`
                                        )

                                        if (action === 'remove' && target) {
                                            const targetElement = document.getElementById(target)
                                            if (targetElement) {
                                                targetElement.remove()
                                                console.log(`🗑️ Removed element: ${target}`)
                                            } else {
                                                console.warn(`⚠️ Target element not found: ${target}`)
                                            }
                                        } else if (action === 'update' && target && template) {
                                            const targetElement = document.getElementById(target)
                                            if (targetElement) {
                                                targetElement.innerHTML = template.innerHTML
                                                console.log(`🔄 Updated element: ${target}`)
                                            } else {
                                                console.warn(`⚠️ Target element not found: ${target}`)
                                            }
                                        }
                                    })

                                    console.log('✅ Turbo Stream processing completed')
                                } else {
                                    console.log('📄 Non-Turbo Stream response, reloading content')
                                    // 如果不是 Turbo Stream，重新載入內容
                                    this.loadTabContent('closure-dates')
                                    return // 早期返回，避免重複執行更新
                                }

                                // 重新檢查已存在的公休設定
                                setTimeout(() => {
                                    console.log('🔄 Starting post-deletion updates...')

                                    if (window.checkExistingClosureDates) {
                                        console.log('🔄 Re-checking existing closure dates after deletion')
                                        window.checkExistingClosureDates()
                                    } else {
                                        console.warn('⚠️ checkExistingClosureDates function not found')
                                    }

                                    if (window.updateStatistics) {
                                        console.log('📊 Updating statistics after deletion')
                                        window.updateStatistics()
                                    } else {
                                        console.warn('⚠️ updateStatistics function not found')
                                    }

                                    console.log('✅ Post-deletion updates completed')
                                }, 200)
                            } else {
                                throw new Error(`HTTP ${response.status}: ${response.statusText}`)
                            }
                        } catch (error) {
                            console.error('💥 Delete failed:', error)
                            alert('刪除失敗，請稍後再試')
                        }
                    }
                })
            }
        })

        // 在載入完成後檢查已存在的公休設定
        setTimeout(() => {
            if (window.checkExistingClosureDates) {
                console.log('🔄 Calling checkExistingClosureDates after content load')
                window.checkExistingClosureDates()
            } else {
                console.warn('⚠️ checkExistingClosureDates function not found')
            }
        }, 500)
    }

    // 手動處理週幾公休提交（備用方法）
    async manualWeeklySubmit(container) {
        console.log('🔧 Manual weekly submit fallback')

        try {
            const checkboxes = container.querySelectorAll('input[name="weekdays[]"]:checked')
            const reasonField = container.querySelector('input[name*="reason"]')
            const reason = reasonField ? reasonField.value : '每週固定公休'

            console.log('📋 Found checkboxes:', checkboxes.length)
            console.log('📝 Reason:', reason)

            if (checkboxes.length === 0) {
                alert('請至少選擇一個定休日')
                return
            }

            console.log(
                '📋 Selected weekdays:',
                Array.from(checkboxes).map((cb) => cb.value)
            )

            const slug = this.restaurantSlugValue
            const url = `/admin/restaurant_settings/restaurants/${slug}/closure_dates`

            console.log('🌐 Using slug:', slug)
            console.log('🌐 Using URL:', url)

            // 獲取 CSRF token
            const csrfToken = this.getCSRFToken()
            console.log('🔐 CSRF token found:', !!csrfToken)

            if (!csrfToken) {
                console.error('❌ CSRF token not found')
                alert('找不到安全令牌')
                return
            }

            console.log('🚀 Starting requests...')

            const promises = Array.from(checkboxes).map(async (checkbox, index) => {
                const weekday = parseInt(checkbox.value)
                console.log(`📅 Processing weekday ${index + 1}/${checkboxes.length}: ${weekday}`)

                // 計算下一個對應的星期幾日期
                const today = new Date()
                const todayWeekday = today.getDay() === 0 ? 7 : today.getDay()
                let daysToAdd = weekday - todayWeekday
                if (daysToAdd <= 0) {
                    daysToAdd += 7
                }
                const targetDate = new Date(today)
                targetDate.setDate(today.getDate() + daysToAdd)

                console.log(`📅 Target date for weekday ${weekday}:`, targetDate.toISOString().split('T')[0])

                const formData = new FormData()
                formData.append('closure_date[date]', targetDate.toISOString().split('T')[0])
                formData.append('closure_date[reason]', reason)
                formData.append('closure_date[closure_type]', 'regular')
                formData.append('closure_date[all_day]', 'true')
                formData.append('closure_date[recurring]', 'true')
                formData.append('closure_date[recurring_pattern]', JSON.stringify({ type: 'weekly', weekday: weekday }))

                console.log(`📦 Sending request ${index + 1} to:`, url)

                const response = await fetch(url, {
                    method: 'POST',
                    body: formData,
                    headers: {
                        'X-CSRF-Token': csrfToken,
                        Accept: 'text/vnd.turbo-stream.html',
                        'X-Requested-With': 'XMLHttpRequest',
                    },
                })

                console.log(`📡 Response ${index + 1}:`, response.status, response.statusText)

                if (!response.ok) {
                    const errorText = await response.text()
                    console.error(`❌ Request ${index + 1} failed:`, errorText)
                    throw new Error(`HTTP ${response.status}: ${response.statusText}`)
                }

                const responseText = await response.text()
                console.log(`✅ Request ${index + 1} success:`, responseText.substring(0, 100) + '...')

                return response
            })

            await Promise.all(promises)
            console.log('🎉 All requests completed successfully!')
            alert('設定成功！')

            // 重置表單
            checkboxes.forEach((checkbox) => (checkbox.checked = false))
            console.log('🔄 Form reset')

            // 重新載入公休日內容
            this.loadTabContent('closure-dates')
        } catch (error) {
            console.error('💥 Manual submission failed:', error)
            console.error('💥 Error stack:', error.stack)
            alert(`設定失敗：${error.message}`)
        }
    }

    // 通用表單初始化
    initializeForms(contentDiv, tabName) {
        const forms = contentDiv.querySelectorAll('form:not([data-processed])')
        forms.forEach((form) => {
            // 標記為已處理
            form.setAttribute('data-processed', 'true')

            // 確保表單使用 Turbo
            if (!form.hasAttribute('data-turbo')) {
                form.setAttribute('data-turbo', 'true')
            }

            // 綁定刪除按鈕
            const deleteButtons = form.querySelectorAll(
                'a[data-turbo-method="delete"], button[data-turbo-method="delete"]'
            )
            deleteButtons.forEach((button) => {
                button.addEventListener('click', async (e) => {
                    e.preventDefault()

                    if (confirm(button.dataset.confirm || '確定要刪除嗎？')) {
                        try {
                            const url = button.href || button.dataset.url
                            const response = await fetch(url, {
                                method: 'DELETE',
                                headers: {
                                    'X-CSRF-Token': this.getCSRFToken(),
                                    Accept: 'text/vnd.turbo-stream.html',
                                },
                            })

                            if (response.ok) {
                                // 重新載入選項卡內容
                                this.loadTabContent(tabName)
                            }
                        } catch (error) {
                            console.error('💥 刪除失敗:', error)
                            alert('刪除失敗，請稍後再試')
                        }
                    }
                })
            })
        })
    }

    // 載入編輯內容到 modal
    async loadEditContent(url) {
        try {
            console.log('🔧 Loading edit content from:', url)
            const response = await fetch(url, {
                headers: {
                    Accept: 'text/html',
                    'X-Requested-With': 'XMLHttpRequest',
                },
            })

            const html = await response.text()
            const parser = new DOMParser()
            const doc = parser.parseFromString(html, 'text/html')
            const content = doc.querySelector('.max-w-7xl') || doc.body

            // 確保有編輯模態視窗容器
            let modal = document.getElementById('modal')
            if (!modal) {
                console.log('🔧 Creating edit modal')
                // 創建編輯模態視窗
                modal = document.createElement('div')
                modal.id = 'modal'
                modal.className = 'fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50'
                modal.innerHTML = `
                    <div class="relative top-10 mx-auto p-0 border w-full max-w-4xl shadow-lg rounded-md bg-white min-h-96 max-h-screen overflow-y-auto">
                        <div class="flex items-center justify-between p-6 border-b border-gray-200">
                            <h3 class="text-xl font-semibold text-gray-900">編輯</h3>
                            <button type="button" 
                                    onclick="this.closest('#modal').classList.add('hidden')"
                                    class="text-gray-400 hover:text-gray-600 edit-modal-close">
                                <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                                </svg>
                            </button>
                        </div>
                        <div id="modal-content" class="p-6"></div>
                    </div>
                `
                document.body.appendChild(modal)

                // 點擊背景關閉模態視窗
                modal.addEventListener('click', (e) => {
                    if (e.target === modal) {
                        console.log('🔒 Closing edit modal from background click')
                        modal.classList.add('hidden')
                    }
                })
            }

            const modalContent = modal.querySelector('#modal-content')
            if (modalContent) {
                modalContent.innerHTML = content.innerHTML
                modal.classList.remove('hidden')
                console.log('✅ Edit modal opened successfully')

                // 重新綁定表單提交事件
                this.bindEditFormEvents(modal)
            }
        } catch (error) {
            console.error('💥 載入編輯內容失敗:', error)
            alert('載入失敗，請稍後再試')
        }
    }

    // 綁定編輯表單事件
    bindEditFormEvents(modal) {
        console.log('🔧 Binding edit form events')

        const form = modal.querySelector('form')
        if (form) {
            // 移除舊的事件監聽器
            form.removeEventListener('submit', this.handleEditFormSubmit)

            // 綁定新的事件監聽器
            this.handleEditFormSubmit = async (e) => {
                e.preventDefault()
                console.log('📝 Edit form submitted')

                try {
                    const formData = new FormData(form)
                    const response = await fetch(form.action, {
                        method: form.method || 'PATCH',
                        body: formData,
                        headers: {
                            'X-CSRF-Token': this.getCSRFToken(),
                            Accept: 'text/vnd.turbo-stream.html',
                        },
                    })

                    if (response.ok) {
                        console.log('✅ Form updated successfully')
                        // 關閉編輯模態視窗
                        modal.classList.add('hidden')

                        // 重新載入對應的標籤頁內容
                        if (this.currentTabValue) {
                            this.loadTabContent(this.currentTabValue)
                        }
                    } else {
                        throw new Error('更新失敗')
                    }
                } catch (error) {
                    console.error('💥 更新失敗:', error)
                    alert('更新失敗，請稍後再試')
                }
            }

            form.addEventListener('submit', this.handleEditFormSubmit)
        }

        // 綁定所有取消和關閉按鈕
        const cancelButtons = modal.querySelectorAll('button, a')
        cancelButtons.forEach((button) => {
            const buttonText = button.textContent.trim()
            const isCloseButton =
                buttonText.includes('取消') ||
                buttonText.includes('關閉') ||
                buttonText.includes('×') ||
                button.classList.contains('edit-modal-close') ||
                (button.type === 'button' && !button.closest('form'))

            if (isCloseButton) {
                button.addEventListener('click', (e) => {
                    e.preventDefault()
                    console.log('🔒 Closing edit modal from button click')
                    modal.classList.add('hidden')
                })
            }
        })

        // 綁定頂部關閉按鈕
        const topCloseButton = modal.querySelector('.edit-modal-close')
        if (topCloseButton) {
            topCloseButton.addEventListener('click', () => {
                console.log('🔒 Closing edit modal from top close button')
                modal.classList.add('hidden')
            })
        }
    }

    // 關閉編輯 modal
    closeEditModal() {
        console.log('🔒 Closing edit modal via action')
        const modal = document.getElementById('modal')
        if (modal) {
            console.log('✅ Edit modal found, adding hidden class')
            modal.classList.add('hidden')
            console.log('✅ Edit modal closed successfully')
        } else {
            console.error('❌ Edit modal not found!')
        }
    }

    // 顯示載入狀態
    showLoading(contentDiv) {
        contentDiv.innerHTML = `
      <div class="text-center py-8">
        <div class="inline-flex items-center px-4 py-2 bg-blue-100 text-blue-800 rounded-lg">
          <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-blue-600" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 0 1 8-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 0 1 4 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          載入中...
        </div>
      </div>
    `
    }

    // 顯示錯誤訊息
    showError(contentDiv, message) {
        contentDiv.innerHTML = `
      <div class="text-center py-8 text-red-600">
        ${message}
      </div>
    `
    }

    // 獲取 CSRF Token
    getCSRFToken() {
        return document.querySelector('[name="csrf-token"]').content
    }

    // 關閉 modal 通用方法
    closeModal(modalId) {
        const modal = document.getElementById(modalId)
        if (modal) {
            modal.classList.add('hidden')
        }
    }

    // 開啟 modal 通用方法
    openModalById(modalId) {
        const modal = document.getElementById(modalId)
        if (modal) {
            modal.classList.remove('hidden')
        }
    }

    // 建立國定假日公休
    async createHolidayClosures() {
        const selectedHolidays = document.querySelectorAll('#holidayClosureModal input[type="checkbox"]:checked')

        if (selectedHolidays.length === 0) {
            alert('請選擇至少一個國定假日')
            return
        }

        const promises = []
        const slug = this.restaurantSlugValue

        selectedHolidays.forEach((checkbox) => {
            const dates = checkbox.value.split(',')
            const holidayName = checkbox.dataset.name

            dates.forEach((date) => {
                const promise = fetch(`/admin/restaurant_settings/restaurants/${slug}/closure_dates`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-Token': this.getCSRFToken(),
                    },
                    body: JSON.stringify({
                        closure_date: {
                            date: date,
                            reason: holidayName,
                            closure_type: 'holiday',
                            all_day: true,
                            recurring: false,
                        },
                    }),
                })

                promises.push(promise)
            })
        })

        try {
            await Promise.all(promises)

            // 關閉 modal
            this.closeModal('holidayClosureModal')

            // 重新載入公休日內容
            setTimeout(() => {
                this.loadTabContent('closure-dates')
            }, 1000)
        } catch (error) {
            console.error('💥 建立國定假日失敗:', error)
            alert('建立失敗，請稍後再試')
        }
    }

    // 重新初始化 Stimulus 控制器
    reinitializeStimulusControllers(contentDiv) {
        console.log('🔄 Reinitializing Stimulus controllers...')

        // 尋找所有有 data-controller 屬性的元素
        const controllerElements = contentDiv.querySelectorAll('[data-controller]')

        controllerElements.forEach((element) => {
            const controllerNames = element.dataset.controller.split(' ')
            console.log(`🎯 Found element with controllers: ${controllerNames.join(', ')}`)
        })

        // 檢查並呼叫特定的全域函數
        setTimeout(() => {
            if (typeof window.checkExistingClosureDates === 'function') {
                console.log('✅ Calling checkExistingClosureDates...')
                window.checkExistingClosureDates()
            } else {
                console.warn('⚠️ checkExistingClosureDates function not found')
            }
        }, 200)

        console.log('✅ Controller reinitialization requested')
    }
}
