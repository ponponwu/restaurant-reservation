require 'rails_helper'

RSpec.describe BusinessPeriod do
  describe 'bitmask functionality' do
    let(:business_period) { described_class.new }

    describe 'DAYS_OF_WEEK constant' do
      it 'defines correct bitmask values' do
        expect(BusinessPeriod::DAYS_OF_WEEK[:monday]).to eq(1)
        expect(BusinessPeriod::DAYS_OF_WEEK[:tuesday]).to eq(2)
        expect(BusinessPeriod::DAYS_OF_WEEK[:wednesday]).to eq(4)
        expect(BusinessPeriod::DAYS_OF_WEEK[:thursday]).to eq(8)
        expect(BusinessPeriod::DAYS_OF_WEEK[:friday]).to eq(16)
        expect(BusinessPeriod::DAYS_OF_WEEK[:saturday]).to eq(32)
        expect(BusinessPeriod::DAYS_OF_WEEK[:sunday]).to eq(64)
      end
    end

    describe '#days_of_week=' do
      it 'converts array of day names to bitmask' do
        business_period.days_of_week = %w[monday wednesday friday]
        # monday(1) + wednesday(4) + friday(16) = 21
        expect(business_period.days_of_week_mask).to eq(21)
      end

      it 'handles empty array' do
        business_period.days_of_week = []
        expect(business_period.days_of_week_mask).to eq(0)
      end

      it 'handles nil value' do
        business_period.days_of_week = nil
        expect(business_period.days_of_week_mask).to eq(0)
      end

      it 'ignores invalid day names' do
        business_period.days_of_week = %w[monday invalid_day friday]
        # monday(1) + friday(16) = 17
        expect(business_period.days_of_week_mask).to eq(17)
      end
    end

    describe '#days_of_week' do
      it 'converts bitmask back to array of day names' do
        business_period.days_of_week_mask = 21 # monday(1) + wednesday(4) + friday(16)
        expect(business_period.days_of_week).to contain_exactly('monday', 'wednesday', 'friday')
      end

      it 'returns empty array for zero mask' do
        business_period.days_of_week_mask = 0
        expect(business_period.days_of_week).to eq([])
      end

      it 'handles all days of week' do
        business_period.days_of_week_mask = 127 # 1+2+4+8+16+32+64 = all days
        expect(business_period.days_of_week).to contain_exactly(
          'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'
        )
      end
    end

    describe '#operates_on_day?' do
      before do
        business_period.days_of_week = %w[monday wednesday friday]
      end

      it 'returns true for operating days' do
        expect(business_period.operates_on_day?(:monday)).to be true
        expect(business_period.operates_on_day?('wednesday')).to be true
        expect(business_period.operates_on_day?('FRIDAY')).to be true
      end

      it 'returns false for non-operating days' do
        expect(business_period.operates_on_day?(:tuesday)).to be false
        expect(business_period.operates_on_day?('saturday')).to be false
        expect(business_period.operates_on_day?('sunday')).to be false
      end

      it 'returns false for invalid input' do
        expect(business_period.operates_on_day?(nil)).to be false
        expect(business_period.operates_on_day?(123)).to be false
      end
    end

    describe '#chinese_days_of_week' do
      it 'returns Chinese day names' do
        business_period.days_of_week = %w[monday wednesday friday]
        expect(business_period.chinese_days_of_week).to contain_exactly('星期一', '星期三', '星期五')
      end
    end

    describe '#formatted_days_of_week' do
      it 'returns formatted Chinese day names' do
        business_period.days_of_week = %w[monday wednesday friday]
        expect(business_period.formatted_days_of_week).to eq('星期一、星期三、星期五')
      end
    end
  end
end
