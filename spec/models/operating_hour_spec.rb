require 'rails_helper'

RSpec.describe OperatingHour, type: :model do
  let(:restaurant) { create(:restaurant) }

  describe 'associations' do
    it { is_expected.to belong_to(:restaurant) }
  end

  describe 'validations' do
    subject { build(:operating_hour, restaurant: restaurant) }

    it { is_expected.to validate_presence_of(:weekday) }
    it { is_expected.to validate_inclusion_of(:weekday).in_range(0..6) }
    it { is_expected.to validate_presence_of(:open_time) }
    it { is_expected.to validate_presence_of(:close_time) }

    it 'validates close_time is after open_time' do
      operating_hour = build(:operating_hour, 
                            restaurant: restaurant,
                            open_time: Time.parse('18:00'),
                            close_time: Time.parse('12:00'))
      expect(operating_hour).not_to be_valid
      expect(operating_hour.errors[:close_time]).to be_present
    end
  end

  describe 'scopes' do
    let!(:monday_hours) { create(:operating_hour, restaurant: restaurant, weekday: 1) }
    let!(:tuesday_hours) { create(:operating_hour, restaurant: restaurant, weekday: 2) }

    it 'filters by weekday' do
      expect(OperatingHour.where(weekday: 1)).to include(monday_hours)
      expect(OperatingHour.where(weekday: 1)).not_to include(tuesday_hours)
    end
  end

  describe 'factory' do
    it 'creates valid operating hour' do
      operating_hour = create(:operating_hour)
      expect(operating_hour).to be_valid
      expect(operating_hour.restaurant).to be_present
      expect(operating_hour.weekday).to be_between(0, 6)
    end
  end
end
