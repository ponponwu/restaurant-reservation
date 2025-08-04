require 'rails_helper'

RSpec.describe SmsNotificationJob, type: :job do
  let(:restaurant) { create(:restaurant) }
  let(:reservation) { create(:reservation, :confirmed, restaurant: restaurant) }
  let(:job) { described_class.new }

  before do
    # 設定測試環境變數
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SMS_SERVICE_ENABLED').and_return('true')
    allow(ENV).to receive(:[]).with('SMS_SERVICE_URL').and_return('https://api.example.com/sms')
    allow(ENV).to receive(:[]).with('SMS_SERVICE_API_KEY').and_return('test-api-key')
    allow(ENV).to receive(:[]).with('SMS_SERVICE_FROM').and_return('測試餐廳')
  end

  describe '#perform' do
    context 'with reservation confirmation' do
      it 'sends confirmation SMS successfully' do
        expect do
          job.perform(reservation.id, 'reservation_confirmation')
        end.to change(SmsLog, :count).by(1)

        sms_log = SmsLog.last
        expect(sms_log.message_type).to eq('reservation_confirmation')
        expect(sms_log.status).to eq('sent')
        expect(sms_log.reservation).to eq(reservation)
      end

      it 'logs success message' do
        expect(Rails.logger).to receive(:info).with(/SmsNotificationJob: Processing reservation_confirmation/)
        expect(Rails.logger).to receive(:info).with(/SmsNotificationJob: Successfully processed/)

        job.perform(reservation.id, 'reservation_confirmation')
      end
    end

    context 'with dining reminder' do
      it 'sends reminder SMS successfully' do
        expect do
          job.perform(reservation.id, 'dining_reminder')
        end.to change(SmsLog, :count).by(1)

        sms_log = SmsLog.last
        expect(sms_log.message_type).to eq('dining_reminder')
        expect(sms_log.status).to eq('sent')
      end
    end

    context 'with reservation cancellation' do
      let(:reservation) { create(:reservation, :cancelled, restaurant: restaurant) }
      let(:cancellation_reason) { '客戶主動取消' }

      it 'sends cancellation SMS successfully' do
        expect do
          job.perform(reservation.id, 'reservation_cancellation', { cancellation_reason: cancellation_reason })
        end.to change(SmsLog, :count).by(1)

        sms_log = SmsLog.last
        expect(sms_log.message_type).to eq('reservation_cancellation')
        expect(sms_log.status).to eq('sent')
        expect(sms_log.content).to include(cancellation_reason)
      end
    end

    context 'with invalid reservation' do
      it 'handles missing reservation' do
        expect(Rails.logger).to receive(:error).with(/Reservation 99999 not found/)

        expect do
          job.perform(99999, 'reservation_confirmation')
        end.not_to change(SmsLog, :count)
      end

      it 'skips invalid reservation status' do
        pending_reservation = create(:reservation, :pending, restaurant: restaurant)

        expect(Rails.logger).to receive(:warn).with(/Reservation .+ not valid for dining_reminder/)

        expect do
          job.perform(pending_reservation.id, 'dining_reminder')
        end.not_to change(SmsLog, :count)
      end
    end

    context 'with unknown message type' do
      it 'raises ArgumentError' do
        expect do
          job.perform(reservation.id, 'unknown_type')
        end.to raise_error(ArgumentError, 'Unknown message type: unknown_type')
      end
    end

    context 'with SMS service error' do
      before do
        allow_any_instance_of(SmsService).to receive(:send_reservation_confirmation)
          .and_return({ success: false, error: 'Network error' })
      end

      it 'raises error and retries' do
        expect do
          job.perform(reservation.id, 'reservation_confirmation')
        end.to raise_error(StandardError, 'Failed to send confirmation SMS: Network error')
      end
    end
  end

  describe 'reservation validation' do
    it 'validates confirmed reservation for confirmation' do
      result = job.send(:reservation_valid_for_notification?, reservation, 'reservation_confirmation')
      expect(result).to be true
    end

    it 'validates confirmed reservation for reminder' do
      result = job.send(:reservation_valid_for_notification?, reservation, 'dining_reminder')
      expect(result).to be true
    end

    it 'validates cancelled reservation for cancellation' do
      reservation.update(status: 'cancelled')
      result = job.send(:reservation_valid_for_notification?, reservation, 'reservation_cancellation')
      expect(result).to be true
    end

    it 'rejects pending reservation for reminder' do
      reservation.update(status: 'pending')
      result = job.send(:reservation_valid_for_notification?, reservation, 'dining_reminder')
      expect(result).to be false
    end

    it 'rejects past reservation for reminder' do
      reservation.update(reservation_datetime: 1.day.ago)
      result = job.send(:reservation_valid_for_notification?, reservation, 'dining_reminder')
      expect(result).to be false
    end
  end

  describe 'job configuration' do
    it 'uses default queue' do
      expect(described_class.queue_name).to eq('default')
    end

    it 'has retry configuration' do
      expect(described_class.retry_on_queue_name).to be_present
    end
  end
end
