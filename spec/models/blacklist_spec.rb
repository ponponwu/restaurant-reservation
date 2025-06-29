require 'rails_helper'

RSpec.describe Blacklist do
  # 1. 關聯測試
  describe 'associations' do
    it { is_expected.to belong_to(:restaurant) }
    it { is_expected.to belong_to(:added_by).class_name('User').optional }
  end

  # 2. 驗證測試
  describe 'validations' do
    let(:restaurant) { create(:restaurant) }
    let(:user) { create(:user, :admin, restaurant: restaurant) }
    
    subject { build(:blacklist, restaurant: restaurant, added_by: user) }

    describe 'customer_name' do
      it { is_expected.to validate_presence_of(:customer_name) }
      it { is_expected.to validate_length_of(:customer_name).is_at_most(100) }
    end

    describe 'customer_phone' do
      it { is_expected.to validate_presence_of(:customer_phone) }
      
      it 'validates phone format' do
        subject.customer_phone = '12345'
        expect(subject).not_to be_valid
        expect(subject.errors[:customer_phone]).to include('電話號碼格式不正確')
      end

      it 'accepts valid phone numbers' do
        valid_phones = ['0912345678', '02-12345678', '(02)12345678', '0912 345 678']
        valid_phones.each do |phone|
          subject.customer_phone = phone
          expect(subject).to be_valid, "Expected #{phone} to be valid"
        end
      end

      it 'validates uniqueness scoped to restaurant' do
        create(:blacklist, restaurant: restaurant, customer_phone: '0912345678')
        subject.customer_phone = '0912345678'
        expect(subject).not_to be_valid
        expect(subject.errors[:customer_phone]).to include('此電話號碼已在黑名單中')
      end

      it 'allows same phone for different restaurants' do
        other_restaurant = create(:restaurant)
        create(:blacklist, restaurant: other_restaurant, customer_phone: '0912345678')
        subject.customer_phone = '0912345678'
        expect(subject).to be_valid
      end
    end

    describe 'reason' do
      it { is_expected.to validate_length_of(:reason).is_at_most(500) }
      
      it 'allows blank reason' do
        subject.reason = nil
        expect(subject).to be_valid
      end
    end
  end

  # 3. Scope 測試
  describe 'scopes' do
    let(:restaurant) { create(:restaurant) }
    let!(:active_blacklist) { create(:blacklist, restaurant: restaurant, active: true) }
    let!(:inactive_blacklist) { create(:blacklist, restaurant: restaurant, active: false) }
    let!(:older_blacklist) { create(:blacklist, restaurant: restaurant, created_at: 1.day.ago) }

    describe '.active' do
      it 'returns only active blacklists' do
        expect(Blacklist.active).to include(active_blacklist)
        expect(Blacklist.active).not_to include(inactive_blacklist)
      end
    end

    describe '.inactive' do
      it 'returns only inactive blacklists' do
        expect(Blacklist.inactive).to include(inactive_blacklist)
        expect(Blacklist.inactive).not_to include(active_blacklist)
      end
    end

    describe '.recent' do
      it 'orders by created_at desc' do
        recent_blacklists = Blacklist.recent
        expect(recent_blacklists.first.created_at).to be > recent_blacklists.last.created_at
      end
    end
  end

  # 4. 類別方法測試
  describe 'class methods' do
    describe '.blacklisted_phone?' do
      let(:restaurant) { create(:restaurant) }
      let!(:blacklisted_entry) { create(:blacklist, restaurant: restaurant, customer_phone: '0912345678', active: true) }
      let!(:inactive_entry) { create(:blacklist, restaurant: restaurant, customer_phone: '0987654321', active: false) }

      it 'returns true for blacklisted active phone' do
        expect(Blacklist.blacklisted_phone?(restaurant, '0912345678')).to be true
      end

      it 'returns false for inactive blacklisted phone' do
        expect(Blacklist.blacklisted_phone?(restaurant, '0987654321')).to be false
      end

      it 'returns false for non-blacklisted phone' do
        expect(Blacklist.blacklisted_phone?(restaurant, '0911111111')).to be false
      end

      it 'returns false for blank phone' do
        expect(Blacklist.blacklisted_phone?(restaurant, '')).to be false
        expect(Blacklist.blacklisted_phone?(restaurant, nil)).to be false
      end

      it 'handles formatted phone numbers' do
        expect(Blacklist.blacklisted_phone?(restaurant, '091-234-5678')).to be true
        expect(Blacklist.blacklisted_phone?(restaurant, '(09)12-345-678')).to be true
      end

      it 'is scoped to restaurant' do
        other_restaurant = create(:restaurant)
        expect(Blacklist.blacklisted_phone?(other_restaurant, '0912345678')).to be false
      end
    end

    describe '.ransackable_attributes' do
      it 'returns allowed search attributes' do
        expected_attributes = %w[customer_name customer_phone reason active created_at updated_at]
        expect(Blacklist.ransackable_attributes).to match_array(expected_attributes)
      end
    end

    describe '.ransackable_associations' do
      it 'returns allowed search associations' do
        expected_associations = %w[restaurant added_by]
        expect(Blacklist.ransackable_associations).to match_array(expected_associations)
      end
    end
  end

  # 5. 實例方法測試
  describe 'instance methods' do
    let(:restaurant) { create(:restaurant) }
    let(:blacklist) { create(:blacklist, restaurant: restaurant, customer_phone: '0912345678') }

    describe '#deactivate!' do
      it 'sets active to false' do
        expect { blacklist.deactivate! }.to change { blacklist.active }.from(true).to(false)
      end

      it 'persists the change' do
        blacklist.deactivate!
        expect(blacklist.reload.active).to be false
      end
    end

    describe '#activate!' do
      let(:inactive_blacklist) { create(:blacklist, restaurant: restaurant, active: false) }

      it 'sets active to true' do
        expect { inactive_blacklist.activate! }.to change { inactive_blacklist.active }.from(false).to(true)
      end

      it 'persists the change' do
        inactive_blacklist.activate!
        expect(inactive_blacklist.reload.active).to be true
      end
    end

    describe '#sanitized_phone' do
      it 'removes non-digit characters' do
        blacklist.customer_phone = '091-234-5678'
        expect(blacklist.sanitized_phone).to eq('0912345678')
      end

      it 'handles nil phone' do
        blacklist.customer_phone = nil
        expect(blacklist.sanitized_phone).to be_nil
      end
    end

    describe '#display_phone' do
      it 'formats 10-digit mobile numbers starting with 09' do
        blacklist.customer_phone = '0912345678'
        expect(blacklist.display_phone).to eq('0912-345-678')
      end

      it 'returns original for non-standard formats' do
        blacklist.customer_phone = '02-12345678'
        expect(blacklist.display_phone).to eq('02-12345678')
      end

      it 'returns original for short numbers' do
        blacklist.customer_phone = '12345'
        expect(blacklist.display_phone).to eq('12345')
      end

      it 'handles blank phone' do
        blacklist.customer_phone = ''
        expect(blacklist.display_phone).to eq('')
      end
    end

    describe '#added_by_name' do
      context 'when added_by is present' do
        let(:user) { create(:user, :admin, first_name: '管理員', last_name: '張三') }
        let(:blacklist) { create(:blacklist, restaurant: restaurant, added_by: user) }

        it 'returns the user display name' do
          expect(blacklist.added_by_name).to eq(user.display_name)
        end
      end

      context 'when added_by is nil due to direct database update' do
        let(:user) { create(:user, :admin, first_name: '管理員', last_name: '張三') }
        let(:blacklist) { create(:blacklist, restaurant: restaurant, added_by: user) }

        before do
          # Simulate a case where added_by becomes nil (e.g., orphaned record)
          # Since we can't actually set it to null due to DB constraints, 
          # we'll test the method behavior with a stubbed nil added_by
          allow(blacklist).to receive(:added_by).and_return(nil)
        end

        it 'returns default system admin name when added_by is nil' do
          expect(blacklist.added_by_name).to eq('系統管理員')
        end
      end
    end
  end

  # 6. 回調函數測試
  describe 'callbacks' do
    let(:restaurant) { create(:restaurant) }

    describe 'before_validation :sanitize_phone' do
      it 'sanitizes phone number before validation' do
        blacklist = build(:blacklist, restaurant: restaurant, customer_phone: '091-234-5678')
        blacklist.valid?
        expect(blacklist.customer_phone).to eq('0912345678')
      end

      it 'handles phone with parentheses and spaces' do
        blacklist = build(:blacklist, restaurant: restaurant, customer_phone: '(091) 234-5678')
        blacklist.valid?
        expect(blacklist.customer_phone).to eq('0912345678')
      end

      it 'does not modify blank phone' do
        blacklist = build(:blacklist, restaurant: restaurant, customer_phone: '')
        blacklist.valid?
        expect(blacklist.customer_phone).to eq('')
      end
    end
  end

  # 7. 整合測試
  describe 'integration scenarios' do
    let(:restaurant) { create(:restaurant) }
    let(:user) { create(:user, :admin, restaurant: restaurant) }

    context 'creating a blacklist entry' do
      it 'successfully creates with valid attributes' do
        blacklist_attrs = {
          restaurant: restaurant,
          added_by: user,
          customer_name: '問題客戶',
          customer_phone: '091-234-5678',
          reason: '多次無故爽約'
        }

        expect { create(:blacklist, blacklist_attrs) }.to change(Blacklist, :count).by(1)
      end

      it 'automatically sanitizes phone on creation' do
        blacklist = create(:blacklist, 
                          restaurant: restaurant,
                          customer_phone: '(091) 234-5678')
        expect(blacklist.customer_phone).to eq('0912345678')
      end
    end

    context 'phone blacklist checking workflow' do
      let!(:blacklisted_customer) { create(:blacklist, restaurant: restaurant, customer_phone: '0912345678') }

      it 'prevents duplicate entries for same phone' do
        duplicate_entry = build(:blacklist, restaurant: restaurant, customer_phone: '091-234-5678')
        expect(duplicate_entry).not_to be_valid
      end

      it 'allows checking if phone is blacklisted' do
        expect(Blacklist.blacklisted_phone?(restaurant, '0912345678')).to be true
        expect(Blacklist.blacklisted_phone?(restaurant, '0987654321')).to be false
      end

      it 'can deactivate and reactivate entries' do
        blacklisted_customer.deactivate!
        expect(Blacklist.blacklisted_phone?(restaurant, '0912345678')).to be false
        
        blacklisted_customer.activate!
        expect(Blacklist.blacklisted_phone?(restaurant, '0912345678')).to be true
      end
    end
  end
end
