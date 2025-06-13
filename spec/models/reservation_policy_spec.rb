require 'rails_helper'

RSpec.describe ReservationPolicy, type: :model do
  # 1. 測試設定
  let(:restaurant) { create(:restaurant) }
  let(:reservation_policy) { build(:reservation_policy, restaurant: restaurant) }

  # 2. 關聯測試
  describe 'associations' do
    it 'belongs to restaurant' do
      expect(reservation_policy.restaurant).to eq(restaurant)
      expect(reservation_policy).to respond_to(:restaurant)
    end
  end

  # 3. 驗證測試
  describe 'validations' do
    subject { reservation_policy }

    it 'validates presence of advance_booking_days' do
      # 跳過回調來測試驗證
      reservation_policy.advance_booking_days = nil
      reservation_policy.send(:validate)
      expect(reservation_policy.errors[:advance_booking_days]).to include("can't be blank")
    end

    it 'validates presence of minimum_advance_hours' do
      reservation_policy.minimum_advance_hours = nil
      reservation_policy.send(:validate)
      expect(reservation_policy.errors[:minimum_advance_hours]).to include("can't be blank")
    end

    it 'validates presence of max_party_size' do
      reservation_policy.max_party_size = nil
      reservation_policy.send(:validate)
      expect(reservation_policy.errors[:max_party_size]).to include("can't be blank")
    end

    it 'validates presence of min_party_size' do
      reservation_policy.min_party_size = nil
      reservation_policy.send(:validate)
      expect(reservation_policy.errors[:min_party_size]).to include("can't be blank")
    end

    it 'validates presence of deposit_amount' do
      reservation_policy.deposit_amount = nil
      reservation_policy.send(:validate)
      expect(reservation_policy.errors[:deposit_amount]).to include("can't be blank")
    end

    it 'validates presence of max_bookings_per_phone' do
      reservation_policy.max_bookings_per_phone = nil
      reservation_policy.send(:validate)
      expect(reservation_policy.errors[:max_bookings_per_phone]).to include("can't be blank")
    end

    it 'validates presence of phone_limit_period_days' do
      reservation_policy.phone_limit_period_days = nil
      reservation_policy.send(:validate)
      expect(reservation_policy.errors[:phone_limit_period_days]).to include("can't be blank")
    end

    it 'validates advance_booking_days is greater than or equal to 0' do
      reservation_policy.advance_booking_days = -1
      expect(reservation_policy).not_to be_valid
      expect(reservation_policy.errors[:advance_booking_days]).to include("must be greater than or equal to 0")
    end

    it 'validates minimum_advance_hours is greater than or equal to 0' do
      reservation_policy.minimum_advance_hours = -1
      expect(reservation_policy).not_to be_valid
      expect(reservation_policy.errors[:minimum_advance_hours]).to include("must be greater than or equal to 0")
    end

    it 'validates max_party_size is greater than 0' do
      reservation_policy.max_party_size = 0
      expect(reservation_policy).not_to be_valid
      expect(reservation_policy.errors[:max_party_size]).to include("must be greater than 0")
    end

    it 'validates min_party_size is greater than 0' do
      reservation_policy.min_party_size = 0
      expect(reservation_policy).not_to be_valid
      expect(reservation_policy.errors[:min_party_size]).to include("must be greater than 0")
    end

    it 'validates deposit_amount is greater than or equal to 0' do
      reservation_policy.deposit_amount = -1
      expect(reservation_policy).not_to be_valid
      expect(reservation_policy.errors[:deposit_amount]).to include("must be greater than or equal to 0")
    end

    it 'validates max_bookings_per_phone is greater than 0' do
      reservation_policy.max_bookings_per_phone = 0
      expect(reservation_policy).not_to be_valid
      expect(reservation_policy.errors[:max_bookings_per_phone]).to include("must be greater than 0")
    end

    it 'validates phone_limit_period_days is greater than 0' do
      reservation_policy.phone_limit_period_days = 0
      expect(reservation_policy).not_to be_valid
      expect(reservation_policy.errors[:phone_limit_period_days]).to include("must be greater than 0")
    end

    describe 'party size validation' do
      it 'validates min_party_size is not greater than max_party_size' do
        reservation_policy.min_party_size = 10
        reservation_policy.max_party_size = 5
        expect(reservation_policy).not_to be_valid
        expect(reservation_policy.errors[:min_party_size]).to include('最小人數不能大於最大人數')
      end

      it 'allows min_party_size equal to max_party_size' do
        reservation_policy.min_party_size = 5
        reservation_policy.max_party_size = 5
        expect(reservation_policy).to be_valid
      end
    end
  end

  # 4. Scope 測試
  describe 'scopes' do
    let!(:with_deposit) { create(:reservation_policy, :with_deposit, restaurant: create(:restaurant)) }
    let!(:without_deposit) { create(:reservation_policy, restaurant: create(:restaurant)) }

    it 'returns policies with deposit' do
      expect(ReservationPolicy.requiring_deposit).to include(with_deposit)
      expect(ReservationPolicy.requiring_deposit).not_to include(without_deposit)
    end

    it 'returns policies without deposit' do
      expect(ReservationPolicy.not_requiring_deposit).to include(without_deposit)
      expect(ReservationPolicy.not_requiring_deposit).not_to include(with_deposit)
    end
  end

  # 5. 計算方法測試
  describe '#earliest_booking_date' do
    it 'returns correct earliest booking date' do
      reservation_policy.advance_booking_days = 14
      expected_date = Date.current + 14.days
      expect(reservation_policy.earliest_booking_date).to eq(expected_date)
    end
  end

  describe '#latest_booking_datetime' do
    it 'returns correct latest booking datetime' do
      reservation_policy.minimum_advance_hours = 24
      expected_datetime = Time.current + 24.hours
      expect(reservation_policy.latest_booking_datetime).to be_within(1.minute).of(expected_datetime)
    end
  end

  describe '#can_book_on_date?' do
    before do
      reservation_policy.advance_booking_days = 7
      reservation_policy.save!
    end

    it 'returns true for dates within booking window' do
      valid_date = Date.current + 3.days
      expect(reservation_policy.can_book_on_date?(valid_date)).to be true
    end

    it 'returns false for dates beyond booking window' do
      invalid_date = Date.current + 10.days
      expect(reservation_policy.can_book_on_date?(invalid_date)).to be false
    end
  end

  describe '#can_book_at_time?' do
    before do
      reservation_policy.minimum_advance_hours = 24
      reservation_policy.save!
    end

    it 'returns true when booking in time' do
      valid_time = Time.current + 48.hours
      expect(reservation_policy.can_book_at_time?(valid_time)).to be true
    end

    it 'returns false when booking too late' do
      invalid_time = Time.current + 12.hours
      expect(reservation_policy.can_book_at_time?(invalid_time)).to be false
    end
  end

  describe '#party_size_valid?' do
    before do
      reservation_policy.min_party_size = 2
      reservation_policy.max_party_size = 8
      reservation_policy.save!
    end

    it 'returns true for valid party size' do
      expect(reservation_policy.party_size_valid?(4)).to be true
      expect(reservation_policy.party_size_valid?(2)).to be true
      expect(reservation_policy.party_size_valid?(8)).to be true
    end

    it 'returns false for invalid party size' do
      expect(reservation_policy.party_size_valid?(1)).to be false
      expect(reservation_policy.party_size_valid?(10)).to be false
    end
  end

  describe '#calculate_deposit' do
    context 'when deposit not required' do
      before do
        reservation_policy.deposit_required = false
        reservation_policy.save!
      end

      it 'returns 0' do
        expect(reservation_policy.calculate_deposit(4)).to eq(0)
      end
    end

    context 'when deposit required' do
      before do
        reservation_policy.deposit_required = true
        reservation_policy.deposit_amount = 100
      end

      context 'fixed amount deposit' do
        before do
          reservation_policy.deposit_per_person = false
          reservation_policy.save!
        end

        it 'returns fixed amount' do
          expect(reservation_policy.calculate_deposit(4)).to eq(100)
        end
      end

      context 'per person deposit' do
        before do
          reservation_policy.deposit_per_person = true
          reservation_policy.save!
        end

        it 'returns amount per person' do
          expect(reservation_policy.calculate_deposit(4)).to eq(400)
        end
      end
    end
  end

  describe '#formatted_deposit_policy' do
    context 'when deposit not required' do
      before do
        reservation_policy.deposit_required = false
        reservation_policy.save!
      end

      it 'returns no deposit message' do
        expect(reservation_policy.formatted_deposit_policy).to eq('無需押金')
      end
    end

    context 'when deposit required' do
      before do
        reservation_policy.deposit_required = true
        reservation_policy.deposit_amount = 100
      end

      context 'fixed amount' do
        before do
          reservation_policy.deposit_per_person = false
          reservation_policy.save!
        end

        it 'returns fixed amount format' do
          expect(reservation_policy.formatted_deposit_policy).to eq('固定金額 $100')
        end
      end

      context 'per person' do
        before do
          reservation_policy.deposit_per_person = true
          reservation_policy.save!
        end

        it 'returns per person format' do
          expect(reservation_policy.formatted_deposit_policy).to eq('每人 $100')
        end
      end
    end
  end

  # 6. 手機號碼限制測試
  describe 'phone booking limits' do
    let(:phone_number) { '0912345678' }
    
    before do
      reservation_policy.max_bookings_per_phone = 3
      reservation_policy.phone_limit_period_days = 30
      reservation_policy.save!
    end

    describe '#count_phone_bookings_in_period' do
      before do
        # 創建在限制期間內的訂位
        create_list(:reservation, 2,
                   restaurant: restaurant,
                   customer_phone: phone_number,
                   reservation_datetime: 5.days.from_now,
                   status: :confirmed)
        
        # 創建超出限制期間的訂位（不應計算）
        create(:reservation,
               restaurant: restaurant,
               customer_phone: phone_number,
               reservation_datetime: 45.days.from_now,
               status: :confirmed)
        
        # 創建已取消的訂位（不應計算）
        create(:reservation,
               restaurant: restaurant,
               customer_phone: phone_number,
               reservation_datetime: 10.days.from_now,
               status: :cancelled)
      end

      it 'counts reservations within period' do
        count = reservation_policy.count_phone_bookings_in_period(phone_number)
        expect(count).to eq(2)
      end

      it 'returns 0 for blank phone number' do
        count = reservation_policy.count_phone_bookings_in_period('')
        expect(count).to eq(0)
      end
    end

    describe '#phone_booking_limit_exceeded?' do
      it 'returns false when under limit' do
        create(:reservation,
               restaurant: restaurant,
               customer_phone: phone_number,
               reservation_datetime: 5.days.from_now,
               status: :confirmed)
        
        expect(reservation_policy.phone_booking_limit_exceeded?(phone_number)).to be false
      end

      it 'returns true when at limit' do
        create_list(:reservation, 3,
                   restaurant: restaurant,
                   customer_phone: phone_number,
                   reservation_datetime: 5.days.from_now,
                   status: :confirmed)
        
        expect(reservation_policy.phone_booking_limit_exceeded?(phone_number)).to be true
      end

      it 'returns false for blank phone number' do
        expect(reservation_policy.phone_booking_limit_exceeded?('')).to be false
      end
    end

    describe '#remaining_bookings_for_phone' do
      it 'returns correct remaining bookings' do
        create(:reservation,
               restaurant: restaurant,
               customer_phone: phone_number,
               reservation_datetime: 5.days.from_now,
               status: :confirmed)
        
        remaining = reservation_policy.remaining_bookings_for_phone(phone_number)
        expect(remaining).to eq(2)
      end

      it 'returns 0 when at limit' do
        create_list(:reservation, 3,
                   restaurant: restaurant,
                   customer_phone: phone_number,
                   reservation_datetime: 5.days.from_now,
                   status: :confirmed)
        
        remaining = reservation_policy.remaining_bookings_for_phone(phone_number)
        expect(remaining).to eq(0)
      end

      it 'returns max bookings for blank phone number' do
        remaining = reservation_policy.remaining_bookings_for_phone('')
        expect(remaining).to eq(3)
      end
    end

    describe '#formatted_phone_limit_policy' do
      it 'returns formatted policy description' do
        expected = '同一手機號碼在30天內最多只能建立3個有效訂位'
        expect(reservation_policy.formatted_phone_limit_policy).to eq(expected)
      end
    end
  end

  # 7. 訂位開關測試
  describe 'reservation toggle' do
    describe '#accepts_online_reservations?' do
      it 'returns true when reservation enabled' do
        reservation_policy.reservation_enabled = true
        expect(reservation_policy.accepts_online_reservations?).to be true
      end

      it 'returns false when reservation disabled' do
        reservation_policy.reservation_enabled = false
        expect(reservation_policy.accepts_online_reservations?).to be false
      end
    end

    describe '#reservation_disabled_message' do
      it 'returns message when disabled' do
        reservation_policy.reservation_enabled = false
        expected = '線上訂位功能暫停服務，如需訂位請直接致電餐廳'
        expect(reservation_policy.reservation_disabled_message).to eq(expected)
      end

      it 'returns nil when enabled' do
        reservation_policy.reservation_enabled = true
        expect(reservation_policy.reservation_disabled_message).to be_nil
      end
    end
  end

  # 8. 類別方法測試
  describe '.for_restaurant' do
    it 'finds existing policy' do
      existing_policy = create(:reservation_policy, restaurant: restaurant)
      result = ReservationPolicy.for_restaurant(restaurant)
      expect(result.restaurant_id).to eq(existing_policy.restaurant_id)
    end

    it 'creates new policy if not exists' do
      new_restaurant = create(:restaurant)
      expect(new_restaurant.reservation_policy).to be_nil
      
      expect {
        ReservationPolicy.for_restaurant(new_restaurant)
      }.to change(ReservationPolicy, :count).by(1)
    end
  end

  # 9. 回調函數測試
  describe 'callbacks' do
    describe 'before_validation :set_defaults' do
      it 'sets default values' do
        policy = ReservationPolicy.new(restaurant: restaurant)
        policy.valid?
        
        expect(policy.advance_booking_days).to eq(30)
        expect(policy.minimum_advance_hours).to eq(2)
        expect(policy.max_party_size).to eq(10)
        expect(policy.min_party_size).to eq(1)
        expect(policy.max_bookings_per_phone).to eq(5)
        expect(policy.phone_limit_period_days).to eq(30)
        expect(policy.reservation_enabled).to be true
      end
    end

    describe 'before_validation :sanitize_inputs' do
      it 'sanitizes policy text fields' do
        policy = build(:reservation_policy,
                      restaurant: restaurant,
                      no_show_policy: '  測試政策  ',
                      modification_policy: '  修改政策  ')
        policy.valid?
        
        expect(policy.no_show_policy).to eq('測試政策')
        expect(policy.modification_policy).to eq('修改政策')
      end
    end
  end

  # 10. 綜合方法測試
  describe '#booking_rules_summary' do
    it 'returns comprehensive rules summary' do
      policy = create(:reservation_policy,
                     restaurant: restaurant,
                     advance_booking_days: 14,
                     minimum_advance_hours: 4,
                     min_party_size: 2,
                     max_party_size: 6,
                     deposit_required: true,
                     deposit_amount: 200,
                     deposit_per_person: false,
                     max_bookings_per_phone: 2,
                     phone_limit_period_days: 7)
      
      summary = policy.booking_rules_summary
      
      expect(summary).to include('最多提前 14 天預約')
      expect(summary).to include('最少提前 4 小時預約')
      expect(summary).to include('人數限制：2-6 人')
      expect(summary).to include('固定金額 $200')
      expect(summary).to include('單一手機號碼 7 天內最多訂位 2 次')
    end
  end
end 