import { Controller } from '@hotwired/stimulus'
import Sortable from 'sortablejs'

export default class extends Controller {
    static values = {
        groupId: String,
        restaurantId: String,
    }

    connect() {
        console.log('🔥 Sortable controller connected!', this.element)
        console.log('🔥 Element class:', this.element.className)
        console.log('🔥 Child elements:', this.element.children.length)

        // 列出所有可拖曳的元素
        const draggableRows = this.element.querySelectorAll('[data-sortable-id]')
        console.log('🔥 Found draggable rows:', draggableRows.length)

        draggableRows.forEach((row, index) => {
            console.log(`🔥 Row ${index}:`, row.dataset.sortableId, row.dataset.groupId)
        })

        this.initializeSortable()
    }

    disconnect() {
        console.log('🔥 Sortable controller disconnected')
        if (this.sortable) {
            this.sortable.destroy()
        }
    }

    initializeSortable() {
        console.log('🔥 Initializing Sortable...')

        try {
            this.sortable = Sortable.create(this.element, {
                group: 'table-rows',
                animation: 150,
                ghostClass: 'sortable-ghost',
                chosenClass: 'sortable-chosen',
                dragClass: 'sortable-drag',
                handle: '.drag-handle, .group-drag-handle',
                // 移除 filter，允許拖曳群組標題行
                preventOnFilter: false,

                onStart: (evt) => {
                    console.log('🔥 Drag started!', evt.item)
                    evt.item.style.opacity = '0.5'

                    // 如果拖曳的是群組標題行，準備移動整個群組
                    if (evt.item.classList.contains('group-header')) {
                        this.prepareGroupMove(evt.item)
                    }
                },

                onEnd: (evt) => {
                    console.log('🔥 Drag ended!', evt.item)
                    evt.item.style.opacity = '1'

                    // 如果拖曳的是群組標題行，完成群組移動
                    if (evt.item.classList.contains('group-header')) {
                        this.completeGroupMove(evt.item)
                    }

                    this.handleDragEnd(evt)
                },
            })

            console.log('🔥 Sortable created successfully:', this.sortable)
        } catch (error) {
            console.error('🔥 Error creating Sortable:', error)
        }
    }

    handleDragEnd(evt) {
        // 檢查是否拖曳的是群組標題行
        if (evt.item.classList.contains('group-header')) {
            console.log('🔥 Group header drag detected')
            this.handleGroupReorder()
            return
        }

        // 處理桌位拖曳
        const itemId = evt.item.dataset.sortableId
        const oldGroupId = evt.item.dataset.groupId

        console.log('🔥 Handling drag end for item:', itemId, 'from group:', oldGroupId)

        if (!itemId) {
            console.error('🔥 No item ID found!')
            return
        }

        // 找到目標群組
        const newGroupRow = this.findGroupForRow(evt.item)
        const newGroupId = newGroupRow ? newGroupRow.id.replace('group_', '') : oldGroupId

        console.log('🔥 Moving from group:', oldGroupId, 'to group:', newGroupId)

        if (oldGroupId !== newGroupId) {
            console.log('🔥 Cross-group move detected')
            this.moveToGroup(itemId, newGroupId)
            evt.item.dataset.groupId = newGroupId
        } else {
            console.log('🔥 Same-group reorder detected')
            this.updateOrder(newGroupId)
        }
    }

    findGroupForRow(row) {
        let currentElement = row.previousElementSibling

        while (currentElement) {
            if (currentElement.classList.contains('group-header')) {
                console.log('🔥 Found group header:', currentElement.id)
                return currentElement
            }
            currentElement = currentElement.previousElementSibling
        }

        console.log('🔥 No group header found for row')
        return null
    }

    moveToGroup(itemId, newGroupId) {
        console.log('🔥 Moving item', itemId, 'to group', newGroupId)

        const csrfToken = document.querySelector('[name="csrf-token"]').content
        const restaurantId = this.restaurantIdValue || document.body.dataset.restaurantId

        fetch(`/admin/restaurants/${restaurantId}/tables/${itemId}/move_to_group`, {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': csrfToken,
            },
            body: JSON.stringify({
                table_group_id: newGroupId,
            }),
        })
            .then((response) => {
                console.log('🔥 Move response:', response.status)
                return response.json()
            })
            .then((data) => {
                console.log('🔥 Move result:', data)
                if (data.success) {
                    this.showFlash(data.message, 'success')
                    // 重新計算兩個群組的優先順序數字
                    this.updatePriorityNumbers(data.old_group_id)
                    this.updatePriorityNumbers(newGroupId)
                } else {
                    console.error('🔥 Move failed:', data.message)
                    this.showFlash('移動桌位失敗', 'error')
                }
            })
            .catch((error) => {
                console.error('🔥 Move error:', error)
                this.showFlash('網路錯誤，請稍後再試', 'error')
            })
    }

    updateOrder(groupId) {
        console.log('🔥 Updating order for group:', groupId)

        const groupRows = Array.from(this.element.querySelectorAll(`[data-group-id="${groupId}"]`))
        const orderedIds = groupRows.map((row) => row.dataset.sortableId)

        console.log('🔥 New order:', orderedIds)

        if (!groupId || orderedIds.length === 0) {
            console.log('🔥 No group ID or empty order, skipping update')
            return
        }

        const csrfToken = document.querySelector('[name="csrf-token"]').content
        const restaurantId = this.restaurantIdValue || document.body.dataset.restaurantId

        fetch(`/admin/restaurants/${restaurantId}/table_groups/${groupId}/reorder_tables`, {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': csrfToken,
            },
            body: JSON.stringify({
                ordered_ids: orderedIds,
            }),
        })
            .then((response) => {
                console.log('🔥 Reorder response:', response.status)
                return response.json()
            })
            .then((data) => {
                console.log('🔥 Reorder result:', data)
                if (data.success) {
                    this.showFlash(data.message, 'success')
                    this.updatePriorityNumbers(groupId)
                } else {
                    console.error('🔥 Reorder failed:', data.message)
                    this.showFlash('排序更新失敗', 'error')
                }
            })
            .catch((error) => {
                console.error('🔥 Reorder error:', error)
                this.showFlash('網路錯誤，請稍後再試', 'error')
            })
    }

    updatePriorityNumbers(groupId) {
        // 先更新群組內的順序，然後重算全域優先順序
        this.updateGlobalPriorities()
    }

    handleGroupReorder() {
        console.log('🔥 Handling group reorder...')

        // 獲取群組標題行的新順序
        const groupRows = Array.from(this.element.querySelectorAll('.group-header'))
        const orderedGroupIds = groupRows.map((row) => row.dataset.groupSortableId)

        console.log('🔥 New group order:', orderedGroupIds)

        if (orderedGroupIds.length === 0) {
            console.log('🔥 No groups found, skipping reorder')
            return
        }

        this.updateGroupOrder(orderedGroupIds)
    }

    updateGroupOrder(orderedGroupIds) {
        console.log('🔥 Updating group order:', orderedGroupIds)

        const csrfToken = document.querySelector('[name="csrf-token"]').content
        const restaurantId = this.restaurantIdValue

        fetch(`/admin/restaurants/${restaurantId}/table_groups/reorder`, {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': csrfToken,
            },
            body: JSON.stringify({
                ordered_ids: orderedGroupIds,
            }),
        })
            .then((response) => {
                console.log('🔥 Group reorder response:', response.status)
                return response.json()
            })
            .then((data) => {
                console.log('🔥 Group reorder result:', data)
                if (data.success) {
                    this.showFlash(data.message, 'success')
                    this.updateGlobalPriorities()
                } else {
                    console.error('🔥 Group reorder failed:', data.message)
                    this.showFlash('群組排序更新失敗', 'error')
                }
            })
            .catch((error) => {
                console.error('🔥 Group reorder error:', error)
                this.showFlash('網路錯誤，請稍後再試', 'error')
            })
    }

    prepareGroupMove(groupRow) {
        // 準備移動群組：收集該群組的所有桌位行
        const groupId = groupRow.id.replace('group_', '')
        const tableRows = Array.from(this.element.querySelectorAll(`[data-group-id="${groupId}"]`))

        // 儲存桌位行的參考，以便後續移動
        this.movingTableRows = tableRows

        console.log('🔥 Preparing to move group with', tableRows.length, 'tables')
    }

    completeGroupMove(groupRow) {
        // 完成群組移動：將桌位行移動到群組標題行之後
        if (this.movingTableRows && this.movingTableRows.length > 0) {
            const groupId = groupRow.id.replace('group_', '')
            let insertAfter = groupRow

            // 將每個桌位行插入到正確位置
            this.movingTableRows.forEach((tableRow) => {
                // 將桌位行移動到群組標題行之後
                insertAfter.parentNode.insertBefore(tableRow, insertAfter.nextSibling)
                insertAfter = tableRow
            })

            console.log('🔥 Completed group move for', this.movingTableRows.length, 'tables')
        }

        // 清理
        this.movingTableRows = null
    }

    updateGlobalPriorities() {
        console.log('🔥 Updating global priorities...')

        // 使用 Turbo Stream 更新優先順序顯示，而不是重新載入頁面
        const csrfToken = document.querySelector('[name="csrf-token"]').content
        const restaurantId = this.restaurantIdValue

        fetch(`/admin/restaurants/${restaurantId}/table_groups/refresh_priorities`, {
            method: 'GET',
            headers: {
                'Accept': 'text/vnd.turbo-stream.html',
                'X-CSRF-Token': csrfToken,
            },
        })
        .then(response => response.text())
        .then(html => {
            // 讓 Turbo 處理 Stream 響應
            Turbo.renderStreamMessage(html)
        })
        .catch(error => {
            console.error('🔥 Error refreshing priorities:', error)
            // 如果 Turbo Stream 失敗，才使用重新載入作為後備
            setTimeout(() => {
                window.location.reload()
            }, 500)
        })
    }

    showFlash(message, type) {
        const flashContainer = document.getElementById('flash_messages')
        if (flashContainer) {
            const alertClass =
                type === 'success'
                    ? 'bg-green-50 text-green-800 border border-green-200'
                    : 'bg-red-50 text-red-800 border border-red-200'

            const icon =
                type === 'success'
                    ? '<svg class="h-5 w-5 text-green-400" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" /></svg>'
                    : '<svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" /></svg>'

            flashContainer.innerHTML = `
                <div class="rounded-md p-4 mb-4 ${alertClass}">
                    <div class="flex">
                        <div class="flex-shrink-0">${icon}</div>
                        <div class="ml-3">
                            <p class="text-sm font-medium">${message}</p>
                        </div>
                    </div>
                </div>
            `

            setTimeout(() => {
                flashContainer.innerHTML = ''
            }, 3000)
        }
    }
}
