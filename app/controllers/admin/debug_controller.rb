class Admin::DebugController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin_or_dev!

  def user_info
    @user_debug = {
      id: current_user&.id,
      email: current_user&.email,
      first_name: current_user&.first_name,
      last_name: current_user&.last_name,
      role: current_user&.role,
      active: current_user&.active?,
      password_changed_at: current_user&.password_changed_at,
      needs_password_change: current_user&.needs_password_change?,
      can_access_admin: current_user&.can_access_admin?,
      restaurant_id: current_user&.restaurant_id,
      restaurant_name: current_user&.restaurant&.name,
      created_at: current_user&.created_at,
      updated_at: current_user&.updated_at
    }

    render json: @user_debug, status: :ok
  end

  private

  def ensure_admin_or_dev!
    return if Rails.env.development? || current_user&.can_access_admin?

    head :forbidden
  end
end
