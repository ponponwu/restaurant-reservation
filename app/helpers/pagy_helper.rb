module PagyHelper
  def custom_pagy_nav(pagy)
    return '' unless pagy.pages > 1

    content_tag :nav, class: "pagination relative z-0 inline-flex rounded-md shadow-sm -space-x-px", 
                      "aria-label": "分頁" do
      nav_content = ""
      
      # 上一頁
      unless pagy.prev.nil?
        nav_content += link_to(
          raw('<span class="sr-only">上一頁</span><svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z" clip-rule="evenodd" /></svg>'),
          pagy_url_for(pagy, pagy.prev),
          rel: 'prev',
          class: "relative inline-flex items-center px-2 py-2 border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50"
        )
      else
        nav_content += content_tag(:span, 
          raw('<span class="sr-only">上一頁</span><svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z" clip-rule="evenodd" /></svg>'),
          class: "relative inline-flex items-center px-2 py-2 border border-gray-300 bg-gray-100 text-sm font-medium text-gray-400 cursor-not-allowed"
        )
      end
      
      # 頁碼
      pagy.series.each do |item|
        case item
        when Integer
          if item == pagy.page
            nav_content += content_tag(:span, item,
              class: "relative inline-flex items-center px-4 py-2 border border-blue-500 bg-blue-50 text-sm font-medium text-blue-600"
            )
          else
            nav_content += link_to(item, pagy_url_for(pagy, item),
              class: "relative inline-flex items-center px-4 py-2 border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50"
            )
          end
        when String
          nav_content += content_tag(:span, item,
            class: "relative inline-flex items-center px-4 py-2 border border-gray-300 bg-white text-sm font-medium text-gray-500"
          )
        end
      end
      
      # 下一頁
      unless pagy.next.nil?
        nav_content += link_to(
          raw('<span class="sr-only">下一頁</span><svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clip-rule="evenodd" /></svg>'),
          pagy_url_for(pagy, pagy.next),
          rel: 'next',
          class: "relative inline-flex items-center px-2 py-2 border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50"
        )
      else
        nav_content += content_tag(:span,
          raw('<span class="sr-only">下一頁</span><svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clip-rule="evenodd" /></svg>'),
          class: "relative inline-flex items-center px-2 py-2 border border-gray-300 bg-gray-100 text-sm font-medium text-gray-400 cursor-not-allowed"
        )
      end
      
      raw(nav_content)
    end
  end
end