module Admin::DashboardHelper
  def system_status_color(system_status)
    overall_status = overall_system_status(system_status)
    case overall_status
    when 'healthy'
      'bg-green-500'
    when 'warning'
      'bg-yellow-500'
    when 'error'
      'bg-red-500'
    else
      'bg-gray-500'
    end
  end

  def system_status_text(system_status)
    overall_status = overall_system_status(system_status)
    case overall_status
    when 'healthy'
      '正常運行'
    when 'warning'
      '需要注意'
    when 'error'
      '系統異常'
    else
      '未知狀態'
    end
  end

  def activity_icon_class(activity)
    case activity[:icon]
    when 'user'
      'M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z'
    when 'building'
      'M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4'
    else
      'M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z'
    end
  end

  def activity_color_class(activity)
    case activity[:color]
    when 'blue'
      'bg-blue-500'
    when 'green'
      'bg-green-500'
    when 'yellow'
      'bg-yellow-500'
    when 'red'
      'bg-red-500'
    else
      'bg-gray-500'
    end
  end

  def time_ago_in_chinese(time)
    distance = Time.current - time
    
    case distance
    when 0..59
      '剛剛'
    when 60..3599
      "#{(distance / 60).to_i} 分鐘前"
    when 3600..86399
      "#{(distance / 3600).to_i} 小時前"
    when 86400..2591999
      "#{(distance / 86400).to_i} 天前"
    else
      time.strftime('%Y年%m月%d日')
    end
  end

  private

  def overall_system_status(system_status)
    if system_status[:database] == 'error'
      'error'
    elsif system_status.values.include?('warning')
      'warning'
    else
      'healthy'
    end
  end
end 