class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # 1. 關聯定義
  belongs_to :restaurant, optional: true

  # 2. 驗證規則
  validates :first_name, presence: true, length: { maximum: 50 }
  validates :last_name, presence: true, length: { maximum: 50 }
  validates :role, presence: true

  # 3. 枚舉定義
  enum role: { 
    super_admin: 0,  # 系統超級管理員，可管理所有餐廳
    manager: 1,      # 餐廳管理員，可管理特定餐廳
    employee: 2      # 餐廳員工，有限權限
  }

  # 4. Scope 定義
  scope :active, -> { where(active: true, deleted_at: nil) }
  scope :search_by_name_or_email, ->(term) {
    where("first_name ILIKE ? OR last_name ILIKE ? OR email ILIKE ?",
          "%#{term}%", "%#{term}%", "%#{term}%")
  }

  # 5. 回調函數
  before_validation :set_default_values, on: :create
  before_validation :sanitize_inputs

  # 6. 實例方法
  def full_name
    "#{first_name} #{last_name}".strip
  end

  def display_name
    full_name.present? ? full_name : email
  end

  def soft_delete!
    update!(active: false, deleted_at: Time.current)
  end

  def generate_random_password
    self.password = SecureRandom.hex(8)
    self.password_confirmation = password
    self.password_changed_at = nil  # 標記需要強制修改密碼
  end

  def needs_password_change?
    password_changed_at.nil?
  end

  def mark_password_changed!
    update!(password_changed_at: Time.current)
  end

  # 權限檢查方法
  def can_access_admin?
    super_admin? || manager? || employee?
  end

  def can_manage_restaurants?
    super_admin?
  end

  def can_manage_restaurant?(restaurant = nil)
    return true if super_admin?
    return false unless manager? || employee?
    
    # 管理員和員工只能管理自己的餐廳
    restaurant ? self.restaurant == restaurant : self.restaurant.present?
  end

  def can_manage_users?
    super_admin? || manager?
  end

  def can_view_reports?
    super_admin? || manager?
  end

  def role_display_name
    case role
    when 'super_admin'
      '系統管理員'
    when 'manager'
      '餐廳管理員'
    when 'employee'
      '餐廳員工'
    else
      role.humanize
    end
  end

  # 7. 私有方法
  private

  def set_default_values
    self.role ||= 'employee'  # 預設為員工角色
    self.active = true if active.nil?
  end

  def sanitize_inputs
    self.first_name = first_name&.strip
    self.last_name = last_name&.strip
    self.email = email&.strip&.downcase
  end
end
