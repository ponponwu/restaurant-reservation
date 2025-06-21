class Admin::DashboardController < AdminController
  def index
    # 餐廳管理員直接重定向到他們的餐廳管理頁面
    if current_user&.manager? && current_user.restaurant
      redirect_to admin_restaurant_path(current_user.restaurant)
      return
    end

    @stats = dashboard_stats
    @recent_activities = recent_activities
    @system_status = system_status
    @restaurants = Restaurant.active.order(:name) # 添加餐廳列表供選擇
  end

  private

  def dashboard_stats
    {
      total_users: User.active.count,
      total_restaurants: Restaurant.active.count,
      super_admins: User.active.super_admin.count,
      managers: User.active.manager.count,
      employees: User.active.employee.count,
      active_restaurants: Restaurant.active.where(active: true).count,
      inactive_restaurants: Restaurant.active.where(active: false).count,
      total_tables: RestaurantTable.count,
      total_reservations: Reservation.count
    }
  end

  def recent_activities
    # 簡單的活動記錄 - 最近建立的使用者和餐廳
    # 最近建立的使用者
    activities = User.active.order(created_at: :desc).limit(3).map do |user|
      {
        type: 'user_created',
        description: "新管理員 #{user.full_name} 已建立",
        timestamp: user.created_at,
        icon: 'user',
        color: 'blue'
      }
    end

    # 最近建立的餐廳
    Restaurant.active.order(created_at: :desc).limit(3).each do |restaurant|
      activities << {
        type: 'restaurant_created',
        description: "新餐廳 #{restaurant.name} 已建立",
        timestamp: restaurant.created_at,
        icon: 'building',
        color: 'green'
      }
    end

    # 按時間排序並取前5筆
    activities.sort_by { |a| a[:timestamp] }.last(5).reverse
  end

  def system_status
    {
      database: database_status,
      users_health: users_health_status,
      restaurants_health: restaurants_health_status
    }
  end

  def database_status
    ActiveRecord::Base.connection.execute('SELECT 1')
    'healthy'
  rescue StandardError
    'error'
  end

  def users_health_status
    inactive_users = User.where(active: false).count
    total_users = User.count

    if total_users.zero?
      'warning'
    elsif inactive_users.to_f / total_users > 0.3
      'warning'
    else
      'healthy'
    end
  end

  def restaurants_health_status
    inactive_restaurants = Restaurant.where(active: false).count
    total_restaurants = Restaurant.count

    if total_restaurants.zero?
      'warning'
    elsif inactive_restaurants.to_f / total_restaurants > 0.5
      'warning'
    else
      'healthy'
    end
  end
end
