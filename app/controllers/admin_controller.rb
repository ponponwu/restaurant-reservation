class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin_access

  layout 'admin'

  private

  def ensure_admin_access
    return if current_user&.active? && current_user.can_access_admin?

    redirect_to root_path, alert: '您沒有權限存取管理後台'
  end
end
