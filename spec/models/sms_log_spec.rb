require 'rails_helper'

RSpec.describe SmsLog, type: :model do
  let(:restaurant) { create(:restaurant) }
  let(:reservation) { create(:reservation, restaurant: restaurant) }

  describe 'associations' do
    it { is_expected.to belong_to(:reservation) }
  end

  describe 'validations' do
    subject { build(:sms_log, reservation: reservation) }

    it { is_expected.to validate_presence_of(:phone_number) }
    it { is_expected.to validate_presence_of(:message_type) }
    it { is_expected.to validate_presence_of(:content) }
    it { is_expected.to validate_presence_of(:status) }
  end

  describe 'enums or status handling' do
    it 'can have different statuses' do
      sms_log = create(:sms_log, reservation: reservation, status: 'sent')
      expect(sms_log.status).to eq('sent')
      
      sms_log.update!(status: 'failed')
      expect(sms_log.status).to eq('failed')
    end
  end

  describe 'factory' do
    it 'creates valid sms log' do
      sms_log = create(:sms_log, reservation: reservation)
      expect(sms_log).to be_valid
      expect(sms_log.reservation).to be_present
    end
  end
end
