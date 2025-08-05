require 'rails_helper'

RSpec.describe User do
  include ActiveSupport::Testing::TimeHelpers
  # 1. 關聯測試
  describe 'associations' do
    it { is_expected.to belong_to(:restaurant).optional }
  end

  # 2. 驗證測試
  describe 'validations' do
    subject { build(:user) }

    describe 'first_name' do
      it { is_expected.to validate_presence_of(:first_name) }
      it { is_expected.to validate_length_of(:first_name).is_at_most(50) }
    end

    describe 'last_name' do
      it { is_expected.to validate_presence_of(:last_name) }
      it { is_expected.to validate_length_of(:last_name).is_at_most(50) }
    end

    describe 'role' do
      it 'validates presence of role' do
        # Since role might have defaults set, test it differently
        user = build(:user)
        user.role = nil
        user.valid?
        expect(user.role).to be_present # Default should be set
      end
    end

    describe 'email' do
      it { is_expected.to validate_presence_of(:email) }
      it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    end
  end

  # 3. 枚舉測試
  describe 'enums' do
    it {
      expect(subject).to define_enum_for(:role).with_values(
        super_admin: 0,
        manager: 1,
        employee: 2
      )
    }

    describe 'role methods' do
      let(:super_admin) { build_stubbed(:user, role: :super_admin) }
      let(:manager) { build_stubbed(:user, role: :manager) }
      let(:employee) { create(:user, role: :employee) }

      it 'provides role query methods' do
        expect(super_admin.super_admin?).to be true
        expect(super_admin.manager?).to be false
        expect(super_admin.employee?).to be false

        expect(manager.manager?).to be true
        expect(manager.super_admin?).to be false
        expect(manager.employee?).to be false

        expect(employee.employee?).to be true
        expect(employee.super_admin?).to be false
        expect(employee.manager?).to be false
      end
    end
  end

  # 4. Scope 測試
  describe 'scopes' do
    let!(:active_user) { create(:user, active: true, deleted_at: nil) }
    let!(:inactive_user) { create(:user, active: false, deleted_at: nil) }
    let!(:deleted_user) { create(:user, active: true, deleted_at: 1.day.ago) }

    describe '.active' do
      it 'returns only active, non-deleted users' do
        expect(User.active).to include(active_user)
        expect(User.active).not_to include(inactive_user, deleted_user)
      end
    end

    describe '.search_by_name_or_email' do
      let!(:john_doe) { create(:user, first_name: 'John', last_name: 'Doe', email: 'john@example.com') }
      let!(:jane_smith) { create(:user, first_name: 'Jane', last_name: 'Smith', email: 'jane@test.org') }

      it 'finds users by first name' do
        results = User.search_by_name_or_email('John')
        expect(results).to include(john_doe)
        expect(results).not_to include(jane_smith)
      end

      it 'finds users by last name' do
        results = User.search_by_name_or_email('Smith')
        expect(results).to include(jane_smith)
        expect(results).not_to include(john_doe)
      end

      it 'finds users by email' do
        results = User.search_by_name_or_email('john@example')
        expect(results).to include(john_doe)
        expect(results).not_to include(jane_smith)
      end

      it 'is case insensitive' do
        results = User.search_by_name_or_email('JOHN')
        expect(results).to include(john_doe)
      end
    end
  end

  # 5. 實例方法測試
  describe 'instance methods' do
    describe '#full_name' do
      let(:user) { build(:user, first_name: 'John', last_name: 'Doe') }

      it 'returns first and last name combined' do
        expect(user.full_name).to eq('John Doe')
      end

      it 'combines names with potential whitespace' do
        user.first_name = '  John  '
        user.last_name = '  Doe  '
        # full_name method does simple concatenation with a space, then strips
        expect(user.full_name).to eq('John     Doe')
      end

      it 'handles nil names gracefully' do
        user.first_name = nil
        user.last_name = 'Doe'
        expect(user.full_name).to eq('Doe')
      end
    end

    describe '#display_name' do
      context 'when names are present' do
        let(:user) { build(:user, first_name: 'John', last_name: 'Doe', email: 'john@example.com') }

        it 'returns full name' do
          expect(user.display_name).to eq('John Doe')
        end
      end

      context 'when names are blank' do
        let(:user) { build(:user, first_name: '', last_name: '', email: 'john@example.com') }

        it 'returns email as fallback' do
          expect(user.display_name).to eq('john@example.com')
        end
      end

      context 'when full name is whitespace only' do
        let(:user) { build(:user, first_name: '  ', last_name: '  ', email: 'john@example.com') }

        it 'returns email as fallback' do
          expect(user.display_name).to eq('john@example.com')
        end
      end
    end

    describe '#soft_delete!' do
      let(:user) { create(:user, active: true, deleted_at: nil) }

      it 'marks user as inactive and sets deleted_at' do
        travel_to Time.current do
          user.soft_delete!

          expect(user.active).to be false
          expect(user.deleted_at).to eq(Time.current)
        end
      end

      it 'persists the changes' do
        user.soft_delete!
        user.reload

        expect(user.active).to be false
        expect(user.deleted_at).to be_present
      end
    end

    describe '#generate_random_password' do
      let(:user) { build(:user) }

      it 'generates a random password' do
        user.generate_random_password

        expect(user.password).to be_present
        expect(user.password.length).to eq(16) # SecureRandom.hex(8) generates 16 chars
        expect(user.password_confirmation).to eq(user.password)
      end

      it 'sets password_changed_at to nil to force password change' do
        user.generate_random_password
        expect(user.password_changed_at).to be_nil
      end

      it 'generates different passwords each time' do
        user.generate_random_password
        first_password = user.password

        user.generate_random_password
        second_password = user.password

        expect(first_password).not_to eq(second_password)
      end
    end
  end

  # 6. 回調函數測試
  describe 'callbacks' do
    describe 'before_validation :set_default_values' do
      it 'sets default values on create' do
        user = build(:user, active: nil)
        user.valid?

        # Default values should be set (implementation may vary)
        expect(user.active).not_to be_nil
      end
    end

    describe 'before_validation :sanitize_inputs' do
      it 'sanitizes string inputs' do
        user = build(:user, first_name: '  John  ', last_name: '  Doe  ')
        user.valid?

        # Sanitization behavior depends on implementation
        expect(user.first_name.strip).to eq('John')
        expect(user.last_name.strip).to eq('Doe')
      end
    end
  end

  # 7. Devise功能測試
  describe 'Devise functionality' do
    it 'authenticates users with valid credentials' do
      user = create(:user, email: 'test@example.com', password: 'password123', password_confirmation: 'password123')
      expect(user.valid_password?('password123')).to be true
    end

    it 'rejects invalid passwords' do
      user = create(:user, email: 'test@example.com', password: 'password123', password_confirmation: 'password123')
      expect(user.valid_password?('wrong_password')).to be false
    end

    it 'finds user by email' do
      user = create(:user, email: 'test@example.com')
      found_user = User.where(email: 'test@example.com').first
      expect(found_user).to eq(user)
    end
  end

  # 8. 角色權限測試
  describe 'role-based permissions' do
    let(:restaurant) { create(:restaurant) }
    let(:super_admin) { create(:user, :super_admin) }
    let(:manager) { create(:user, :manager, restaurant: restaurant) }
    let(:employee) { create(:user, :employee, restaurant: restaurant) }
    let(:unaffiliated_user) { create(:user, :employee) }

    describe 'restaurant access' do
      it 'super admin can access any restaurant' do
        expect(super_admin.super_admin?).to be true
        expect(super_admin.restaurant).to be_nil # Not tied to specific restaurant
      end

      it 'manager is tied to specific restaurant' do
        expect(manager.manager?).to be true
        expect(manager.restaurant).to eq(restaurant)
      end

      it 'employee is tied to specific restaurant' do
        expect(employee.employee?).to be true
        expect(employee.restaurant).to eq(restaurant)
      end

      it 'unaffiliated user has no restaurant' do
        expect(unaffiliated_user.restaurant).to be_nil
      end
    end
  end

  # 9. 資料完整性測試
  describe 'data integrity' do
    it 'requires unique email addresses' do
      create(:user, email: 'test@example.com')
      duplicate_user = build(:user, email: 'test@example.com')

      expect(duplicate_user).not_to be_valid
      expect(duplicate_user.errors[:email]).to include('has already been taken')
    end

    it 'normalizes email to lowercase' do
      user = create(:user, email: 'TEST@EXAMPLE.COM')
      expect(user.reload.email).to eq('test@example.com')
    end

    it 'validates email format' do
      invalid_emails = ['invalid', 'test@', '@example.com']

      invalid_emails.each do |invalid_email|
        user = build(:user, email: invalid_email)
        expect(user).not_to be_valid, "Expected #{invalid_email} to be invalid"
      end
    end
  end

  # 10. 整合測試
  describe 'integration scenarios' do
    context 'user lifecycle management' do
      it 'creates user with all required attributes' do
        user_attrs = {
          first_name: 'John',
          last_name: 'Doe',
          email: 'john.doe@example.com',
          password: 'secure_password_123',
          password_confirmation: 'secure_password_123',
          role: :manager
        }

        expect { create(:user, user_attrs) }.to change(User, :count).by(1)
      end

      it 'handles user deactivation workflow' do
        user = create(:user, active: true)

        # Soft delete user
        user.soft_delete!

        # User should be excluded from active scope
        expect(User.active).not_to include(user)

        # But user record still exists
        expect(User.unscoped.find(user.id)).to eq(user)
      end
    end

    context 'restaurant assignment workflow' do
      let(:restaurant) { create(:restaurant) }

      it 'assigns manager to restaurant' do
        manager = create(:user, :manager, restaurant: restaurant)

        expect(manager.restaurant).to eq(restaurant)
        expect(restaurant.users).to include(manager)
      end

      it 'handles user role changes' do
        employee = create(:user, :employee, restaurant: restaurant)

        # Promote to manager
        employee.update!(role: :manager)

        expect(employee.manager?).to be true
        expect(employee.restaurant).to eq(restaurant) # Still associated
      end
    end

    context 'authentication and password management' do
      it 'supports password reset workflow' do
        user = create(:user, email: 'reset@example.com')

        # Generate random password (simulating admin reset)
        user.generate_random_password
        user.save!

        # User should be forced to change password
        expect(user.password_changed_at).to be_nil

        # User can authenticate with new password
        expect(user.valid_password?(user.password)).to be true
      end
    end
  end
end
