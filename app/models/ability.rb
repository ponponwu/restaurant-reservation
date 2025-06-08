class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new

    if user.super_admin?
      # 超級管理員可以管理所有資源
      can :manage, :all
    elsif user.manager?
      # 餐廳管理員可以管理自己餐廳的所有資源
      if user.restaurant
        can :manage, Restaurant, id: user.restaurant.id
        can :manage, [RestaurantTable, TableGroup, BusinessPeriod], restaurant_id: user.restaurant.id
        can :read, User, restaurant_id: user.restaurant.id
        can :update, User, id: user.id  # 只能改自己的個人資料
      end
    elsif user.employee?
      # 餐廳員工有有限的權限
      if user.restaurant
        can :read, Restaurant, id: user.restaurant.id
        can :read, [RestaurantTable, TableGroup, BusinessPeriod], restaurant_id: user.restaurant.id
        can :update, User, id: user.id  # 只能改自己的個人資料
        # 可以管理訂位但不能管理設定
        can [:read, :create, :update], Reservation, restaurant_id: user.restaurant.id
      end
    end
  end
end 