class Blacklist < ApplicationRecord
  belongs_to :restaurant
  belongs_to :added_by, class_name: 'User', optional: true

  validates :customer_name, presence: true, length: { maximum: 100 }
  validates :customer_phone, presence: true,
                             format: { with: /\A\d{8,15}\z/, message: '電話號碼格式不正確' },
                             uniqueness: { scope: :restaurant_id, message: '此電話號碼已在黑名單中' }
  validates :reason, length: { maximum: 500 }

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :recent, -> { order(created_at: :desc) }

  # Ransack 搜索屬性白名單
  def self.ransackable_attributes(_auth_object = nil)
    %w[customer_name customer_phone reason active created_at updated_at]
  end

  # Ransack 搜索關聯白名單
  def self.ransackable_associations(_auth_object = nil)
    %w[restaurant added_by]
  end

  def self.blacklisted_phone?(restaurant, phone)
    return false if phone.blank?

    sanitized_phone = phone.gsub(/\D/, '')
    active.exists?(restaurant: restaurant, customer_phone: sanitized_phone)
  end

  def deactivate!
    update!(active: false)
  end

  def activate!
    update!(active: true)
  end

  def sanitized_phone
    customer_phone&.gsub(/\D/, '')
  end

  def display_phone
    return customer_phone if customer_phone.blank?

    phone = customer_phone.gsub(/\D/, '')
    if phone.length == 10 && phone.start_with?('09')
      "#{phone[0..3]}-#{phone[4..6]}-#{phone[7..9]}"
    else
      customer_phone
    end
  end

  # 虛擬屬性：顯示新增者姓名
  def added_by_name
    added_by&.display_name || '系統管理員'
  end

  private

  def sanitize_phone
    return if customer_phone.blank?

    self.customer_phone = customer_phone.gsub(/\D/, '')
  end

  before_validation :sanitize_phone
end
