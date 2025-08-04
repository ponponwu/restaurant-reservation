require 'rails_helper'

RSpec.describe DailyReminderJob, type: :job do
  let(:restaurant) { create(:restaurant) }
  let(:tomorrow) { Date.current.tomorrow }
  let(:job) { described_class.new }

  before do
    # 設定測試環境變數
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SMS_SERVICE_ENABLED').and_return('true')
  end

  describe '#perform' do
    context 'with reservations for tomorrow' do
      let!(:reservation1) { create(:reservation, :confirmed, restaurant: restaurant, reservation_datetime: tomorrow.beginning_of_day + 12.hours) }
      let!(:reservation2) { create(:reservation, :confirmed, restaurant: restaurant, reservation_datetime: tomorrow.beginning_of_day + 19.hours) }
      let!(:cancelled_reservation) { create(:reservation, :cancelled, restaurant: restaurant, reservation_datetime: tomorrow.beginning_of_day + 18.hours) }

      it 'processes confirmed reservations for tomorrow' do
        expect(SmsNotificationJob).to receive(:perform_later).with(reservation1.id, 'dining_reminder')
        expect(SmsNotificationJob).to receive(:perform_later).with(reservation2.id, 'dining_reminder')
        expect(SmsNotificationJob).not_to receive(:perform_later).with(cancelled_reservation.id, 'dining_reminder')

        job.perform(tomorrow)
      end

      it 'logs processing statistics' do
        expect(Rails.logger).to receive(:info).with(/DailyReminderJob: Processing daily reminders for #{tomorrow}/)
        expect(Rails.logger).to receive(:info).with(/DailyReminderJob: Found 2 reservations for #{tomorrow}/)
        expect(Rails.logger).to receive(:info).with(/DailyReminderJob: Completed processing for #{tomorrow}. Success: 2, Errors: 0/)

        job.perform(tomorrow)
      end
    end

    context 'with no reservations' do
      it 'handles empty reservation list' do
        expect(Rails.logger).to receive(:info).with(/DailyReminderJob: No reservations found for #{tomorrow}/)
        expect(SmsNotificationJob).not_to receive(:perform_later)

        job.perform(tomorrow)
      end
    end

    context 'with already sent reminders' do
      let!(:reservation) { create(:reservation, :confirmed, restaurant: restaurant, reservation_datetime: tomorrow.beginning_of_day + 18.hours) }
      let!(:existing_sms_log) { create(:sms_log, :sent, :reminder, reservation: reservation, created_at: Time.current) }

      it 'skips reservations with existing reminders' do
        expect(Rails.logger).to receive(:debug).with(/Reminder already sent for reservation #{reservation.id}/)
        expect(SmsNotificationJob).not_to receive(:perform_later)

        job.perform(tomorrow)
      end
    end

    context 'with default date parameter' do
      it 'defaults to tomorrow when no date provided' do
        expect(job).to receive(:find_reservations_for_reminder).with(tomorrow).and_return([])

        job.perform
      end
    end

    context 'with error handling' do
      let!(:reservation) { create(:reservation, :confirmed, restaurant: restaurant, reservation_datetime: tomorrow.beginning_of_day + 18.hours) }

      it 'handles individual reservation errors' do
        allow(SmsNotificationJob).to receive(:perform_later).and_raise(StandardError.new('Queue error'))

        expect(Rails.logger).to receive(:error).with(/Error queuing reminder for reservation #{reservation.id}/)
        expect(Rails.logger).to receive(:info).with(/Success: 0, Errors: 1/)

        job.perform(tomorrow)
      end

      it 'handles fatal errors' do
        allow(job).to receive(:find_reservations_for_reminder).and_raise(StandardError.new('Database error'))

        expect(Rails.logger).to receive(:error).with(/Fatal error processing daily reminders/)
        expect { job.perform(tomorrow) }.to raise_error(StandardError, 'Database error')
      end
    end

    context 'reservation filtering' do
      let!(:confirmed_reservation) { create(:reservation, :confirmed, restaurant: restaurant, reservation_datetime: tomorrow.beginning_of_day + 18.hours) }
      let!(:pending_reservation) { create(:reservation, :pending, restaurant: restaurant, reservation_datetime: tomorrow.beginning_of_day + 19.hours) }
      let!(:cancelled_reservation) { create(:reservation, :cancelled, restaurant: restaurant, reservation_datetime: tomorrow.beginning_of_day + 20.hours) }
      let!(:no_show_reservation) { create(:reservation, :no_show, restaurant: restaurant, reservation_datetime: tomorrow.beginning_of_day + 21.hours) }
      let!(:no_phone_reservation) { create(:reservation, :confirmed, restaurant: restaurant, reservation_datetime: tomorrow.beginning_of_day + 22.hours, customer_phone: '') }

      it 'only processes confirmed reservations with phone numbers' do
        reservations = job.send(:find_reservations_for_reminder, tomorrow)

        expect(reservations).to include(confirmed_reservation)
        expect(reservations).not_to include(pending_reservation)
        expect(reservations).not_to include(cancelled_reservation)
        expect(reservations).not_to include(no_show_reservation)
        expect(reservations).not_to include(no_phone_reservation)
      end
    end
  end

  describe 'private methods' do
    let!(:reservation) { create(:reservation, :confirmed, restaurant: restaurant, reservation_datetime: tomorrow.beginning_of_day + 18.hours) }

    describe '#already_sent_reminder?' do
      it 'returns false when no reminder sent' do
        result = job.send(:already_sent_reminder?, reservation)
        expect(result).to be false
      end

      it 'returns true when reminder already sent today' do
        create(:sms_log, :sent, :reminder, reservation: reservation, created_at: Time.current)

        result = job.send(:already_sent_reminder?, reservation)
        expect(result).to be true
      end

      it 'returns false when reminder sent yesterday' do
        create(:sms_log, :sent, :reminder, reservation: reservation, created_at: 1.day.ago)

        result = job.send(:already_sent_reminder?, reservation)
        expect(result).to be false
      end

      it 'returns false when reminder failed' do
        create(:sms_log, :failed, :reminder, reservation: reservation, created_at: Time.current)

        result = job.send(:already_sent_reminder?, reservation)
        expect(result).to be false
      end
    end

    describe '#log_reminder_statistics' do
      it 'logs comprehensive statistics' do
        expect(Rails.logger).to receive(:info).with(/=== Daily Reminder Statistics for #{tomorrow} ===/)
        expect(Rails.logger).to receive(:info).with(/Total reservations: 5/)
        expect(Rails.logger).to receive(:info).with(/Successfully queued: 3/)
        expect(Rails.logger).to receive(:info).with(/Errors: 2/)
        expect(Rails.logger).to receive(:info).with(/Success rate: 60.0%/)
        expect(Rails.logger).to receive(:info).with(/=============================================/)

        job.send(:log_reminder_statistics, tomorrow, 5, 3, 2)
      end
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
