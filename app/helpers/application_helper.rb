module ApplicationHelper
  include Pagy::Frontend
  include PagyHelper

  # 側邊導航相關的 helper 方法
  def is_current_page?(path)
    request.path == path
  end

  def is_restaurant_page?(restaurant)
    return false unless restaurant

    request.path == admin_restaurant_path(restaurant) ||
      request.path == edit_admin_restaurant_path(restaurant)
  end

  def is_reservations_page?(restaurant)
    return false unless restaurant

    request.path.start_with?(admin_restaurant_reservations_path(restaurant))
  end

  def is_tables_page?(restaurant)
    return false unless restaurant

    request.path.start_with?(admin_restaurant_table_groups_path(restaurant)) ||
      request.path.start_with?(admin_restaurant_tables_path(restaurant))
  end

  def is_reservation_periods_page?(restaurant)
    return false unless restaurant

    request.path.start_with?(admin_restaurant_reservation_periods_path(restaurant))
  end

  def is_restaurant_settings_page?(restaurant)
    return false unless restaurant

    request.path.start_with?(admin_restaurant_settings_restaurant_index_path(restaurant.slug)) ||
      is_special_dates_page?(restaurant) ||
      is_reservation_policies_page?(restaurant) ||
      is_reservation_periods_settings_page?(restaurant)
  end

  def is_special_dates_page?(restaurant)
    return false unless restaurant

    request.path.start_with?(admin_restaurant_settings_restaurant_special_dates_path(restaurant.slug))
  end

  def is_reservation_policies_page?(restaurant)
    return false unless restaurant

    request.path.start_with?(admin_restaurant_settings_restaurant_reservation_policies_path(restaurant.slug))
  end

  def is_reservation_periods_settings_page?(restaurant)
    return false unless restaurant

    request.path.start_with?(admin_restaurant_settings_restaurant_reservation_periods_path(restaurant.slug))
  end

  def is_blacklists_page?(restaurant)
    return false unless restaurant

    request.path.start_with?(admin_restaurant_blacklists_path(restaurant))
  end
end
