import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    static targets = [
        'partySizeField',
        'adultsField',
        'childrenField',
        'datetimeField',
        'submitButton',
        'phoneInput',
        'phoneError',
    ]
    static values = {
        restaurantId: String,
        checkAvailabilityUrl: String,
    }

    connect() {
        console.log('🔧 Reservation form controller connected')
        this.updateHeadCounts()
    }

    // 更新大人和小孩數量
    updateHeadCounts() {
        if (!this.hasPartySizeFieldTarget || !this.hasAdultsFieldTarget || !this.hasChildrenFieldTarget) {
            return
        }

        const partySize = parseInt(this.partySizeFieldTarget.value) || 1
        const currentAdults = parseInt(this.adultsFieldTarget.value) || 0
        const currentChildren = parseInt(this.childrenFieldTarget.value) || 0
        const currentTotal = currentAdults + currentChildren

        // 如果總人數改變了，需要調整
        if (partySize !== currentTotal) {
            // 保持小孩數不變，調整大人數
            let newAdults = Math.max(partySize - currentChildren, 1) // 至少1個大人
            let newChildren = currentChildren

            // 如果調整後超過總人數，則減少小孩數
            if (newAdults + newChildren > partySize) {
                newChildren = Math.max(partySize - newAdults, 0)
            }

            this.adultsFieldTarget.value = newAdults
            this.childrenFieldTarget.value = newChildren

            console.log(`🔧 人數調整: 總計${partySize} = 大人${newAdults} + 小孩${newChildren}`)
        }
    }

    // 檢查可用性
    async checkAvailability() {
        if (!this.hasDatetimeFieldTarget || !this.hasPartySizeFieldTarget) {
            return
        }

        const datetime = this.datetimeFieldTarget.value
        const partySize = this.partySizeFieldTarget.value

        if (!datetime || !partySize) {
            return
        }

        console.log(`🔧 檢查可用性: ${datetime}, ${partySize}人`)

        try {
            // 這裡可以實作 AJAX 呼叫來檢查可用性
            // const response = await fetch(this.checkAvailabilityUrlValue, {
            //     method: 'POST',
            //     headers: {
            //         'Content-Type': 'application/json',
            //         'X-CSRF-Token': this.getCSRFToken()
            //     },
            //     body: JSON.stringify({
            //         datetime: datetime,
            //         party_size: partySize
            //     })
            // })
            // const result = await response.json()
            // this.displayAvailabilityResult(result)
        } catch (error) {
            console.error('檢查可用性時發生錯誤:', error)
        }
    }

    // 顯示可用性檢查結果
    displayAvailabilityResult(result) {
        const availabilityCheck = document.getElementById('availability_check')
        const availabilityResults = document.getElementById('availability_results')

        if (availabilityCheck && availabilityResults) {
            availabilityCheck.classList.remove('hidden')

            if (result.available) {
                availabilityResults.innerHTML = `
                    <div class="flex items-center p-3 bg-green-50 border border-green-200 rounded-md">
                        <svg class="w-5 h-5 text-green-500 mr-2" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"></path>
                        </svg>
                        <div>
                            <p class="text-sm font-medium text-green-800">有可用桌位</p>
                            <p class="text-sm text-green-700">${result.message}</p>
                        </div>
                    </div>
                `
            } else {
                availabilityResults.innerHTML = `
                    <div class="flex items-center p-3 bg-yellow-50 border border-yellow-200 rounded-md">
                        <svg class="w-5 h-5 text-yellow-500 mr-2" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>
                        </svg>
                        <div>
                            <p class="text-sm font-medium text-yellow-800">桌位不足</p>
                            <p class="text-sm text-yellow-700">${result.message}</p>
                            <p class="text-sm text-blue-600 mt-1">管理員可使用強制模式建立訂位</p>
                        </div>
                    </div>
                `
            }
        }
    }

    // 獲取 CSRF Token
    // getCSRFToken() {
    //     const token = document.querySelector('[name="csrf-token"]')
    //     return token ? token.content : ''
    // }

    // 電話號碼驗證
    validatePhone() {
        if (!this.hasPhoneInputTarget) return true

        const phone = this.phoneInputTarget.value
        const phoneRegex = /^09\d{8}$/
        const isValid = phoneRegex.test(phone)

        if (!isValid) {
            this.phoneErrorTarget.textContent = '請輸入有效的台灣手機號碼 (例如: 0912345678)'
            this.phoneErrorTarget.classList.remove('hidden')
            this.phoneInputTarget.classList.add('border-red-500')
        } else {
            this.phoneErrorTarget.textContent = ''
            this.phoneErrorTarget.classList.add('hidden')
            this.phoneInputTarget.classList.remove('border-red-500')
        }
        return isValid
    }

    // 表單提交前的驗證
    validateForm(event) {
        console.log('validateForm triggered')
        // if (this.hasPartySizeFieldTarget && this.hasAdultsFieldTarget && this.hasChildrenFieldTarget) {
        //     const partySize = parseInt(this.partySizeFieldTarget.value) || 0
        //     const adults = parseInt(this.adultsFieldTarget.value) || 0
        //     const children = parseInt(this.childrenFieldTarget.value) || 0

        //     if (adults + children !== partySize) {
        //         event.preventDefault()
        //         alert('大人數和小孩數的總和必須等於總人數')
        //         return false
        //     }

        //     if (adults < 1) {
        //         event.preventDefault()
        //         alert('至少需要1位大人')
        //         return false
        //     }
        // }
        const isPhoneValid = this.validatePhone()
        if (!isPhoneValid) {
            event.preventDefault()
            return false
        }

        return true
    }

    // 禁用提交按鈕
    disableSubmit() {
        if (this.hasSubmitButtonTarget) {
            this.submitButtonTarget.disabled = true
            this.submitButtonTarget.textContent = '處理中...'
        }
    }

    // 啟用提交按鈕
    enableSubmit() {
        if (this.hasSubmitButtonTarget) {
            this.submitButtonTarget.disabled = false
            this.submitButtonTarget.textContent = this.submitButtonTarget.dataset.originalText || '送出'
        }
    }
}
