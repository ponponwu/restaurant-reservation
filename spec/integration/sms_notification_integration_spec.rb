require 'rails_helper'

RSpec.describe 'SMS Notification Integration', type: :integration do
  let(:restaurant) { create(:restaurant, name: '美食餐廳', phone: '02-12345678') }
  let(:reservation) { create(:reservation, restaurant: restaurant, customer_phone: '0912345678') }

  before do
    # 設定測試環境變數
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SMS_SERVICE_ENABLED').and_return('true')
    allow(ENV).to receive(:[]).with('SMS_SERVICE_URL').and_return('https://api.example.com/sms')
    allow(ENV).to receive(:[]).with('SMS_SERVICE_API_KEY').and_return('test-api-key')
    allow(ENV).to receive(:[]).with('SMS_SERVICE_FROM').and_return('美食餐廳')
  end

  describe 'Reservation Confirmation Workflow' do
    it 'sends SMS when reservation is confirmed' do
      expect do
        reservation.update!(status: 'confirmed')
      end.to change(SmsLog, :count).by(1)

      sms_log = SmsLog.last
      expect(sms_log.message_type).to eq('reservation_confirmation')
      expect(sms_log.status).to eq('sent')
      expect(sms_log.phone_number).to eq('0912345678')
      expect(sms_log.content).to include('美食餐廳 訂位確認')
    end

    it 'sends SMS when reservation is cancelled' do
      reservation.update!(status: 'confirmed')
      SmsLog.destroy_all # 清除確認簡訊記錄

      expect do
        reservation.cancel_by_customer!('臨時有事')
      end.to change(SmsLog, :count).by(1)

      sms_log = SmsLog.last
      expect(sms_log.message_type).to eq('reservation_cancellation')
      expect(sms_log.status).to eq('sent')
      expect(sms_log.content).to include('訂位取消')
      expect(sms_log.content).to include('臨時有事')
    end
  end

  describe 'Daily Reminder Workflow' do
    let(:tomorrow) { Date.current.tomorrow }
    let!(:confirmed_reservation) { create(:reservation, :confirmed, restaurant: restaurant, reservation_datetime: tomorrow.beginning_of_day + 18.hours) }

    it 'processes daily reminders correctly' do
      # 執行每日提醒任務
      expect do
        DailyReminderJob.perform_now(tomorrow)
      end.to change(ActiveJob::Base.queue_adapter.enqueued_jobs, :count).by(1)

      # 檢查是否有 SmsNotificationJob 被加入隊列
      enqueued_job = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      expect(enqueued_job[:job]).to eq(SmsNotificationJob)
      expect(enqueued_job[:args]).to include(confirmed_reservation.id, 'dining_reminder')
    end

    it 'sends reminder SMS through the complete workflow' do
      # 直接執行提醒作業
      expect do
        SmsNotificationJob.perform_now(confirmed_reservation.id, 'dining_reminder')
      end.to change(SmsLog, :count).by(1)

      sms_log = SmsLog.last
      expect(sms_log.message_type).to eq('dining_reminder')
      expect(sms_log.status).to eq('sent')
      expect(sms_log.content).to include('用餐提醒')
      expect(sms_log.content).to include('提醒您明天的用餐時間')
    end
  end

  describe 'Error Handling Workflow' do
    context 'when SMS service is disabled' do
      before do
        allow(ENV).to receive(:[]).with('SMS_SERVICE_ENABLED').and_return('false')
      end

      it 'skips SMS sending' do
        expect do
          reservation.update!(status: 'confirmed')
        end.not_to change(SmsLog, :count)
      end
    end

    context 'when phone number is missing' do
      before do
        reservation.update!(customer_phone: '')
      end

      it 'skips SMS sending' do
        expect do
          reservation.update!(status: 'confirmed')
        end.not_to change(SmsLog, :count)
      end
    end

    context 'when SMS service fails' do
      before do
        # 模擬 SMS 服務失敗
        allow_any_instance_of(SmsService).to receive(:send_reservation_confirmation)
          .and_return({ success: false, error: 'API error' })
      end

      it 'logs error and continues' do
        expect(Rails.logger).to receive(:error).with(/Failed to queue SMS notification/)

        expect do
          reservation.update!(status: 'confirmed')
        end.not_to change(SmsLog, :count)
      end
    end
  end

  describe 'SMS Content Verification' do
    let(:reservation_with_details) do
      create(:reservation, :confirmed,
             restaurant: restaurant,
             customer_name: '王小明',
             customer_phone: '0987654321',
             party_size: 4,
             children_count: 2,
             special_requests: '素食餐點')
    end

    it 'includes all relevant information in confirmation SMS' do
      sms_service = SmsService.new
      result = sms_service.send_reservation_confirmation(reservation_with_details)

      content = result[:sms_log].content
      expect(content).to include('🍽️ 美食餐廳 訂位確認')
      expect(content).to include('👤 訂位人：王小明')
      expect(content).to include('👥 用餐人數：4人 (含兒童 2人)')
      expect(content).to include('📝 特殊要求：素食餐點')
      expect(content).to include('📞 如需異動或取消，請撥打：02-12345678')
      expect(content).to include('期待您的光臨！🌟')
    end

    it 'includes restaurant information in reminder SMS' do
      sms_service = SmsService.new
      result = sms_service.send_dining_reminder(reservation_with_details)

      content = result[:sms_log].content
      expect(content).to include('⏰ 美食餐廳 用餐提醒')
      expect(content).to include('👤 王小明 您好')
      expect(content).to include('提醒您明天的用餐時間')
      expect(content).to include('📞 電話：02-12345678')
    end
  end

  describe 'Performance and Scalability' do
    it 'handles multiple reservations efficiently' do
      reservations = create_list(:reservation, 10, :confirmed, restaurant: restaurant)

      start_time = Time.current

      reservations.each do |res|
        SmsNotificationJob.perform_now(res.id, 'reservation_confirmation')
      end

      end_time = Time.current
      processing_time = end_time - start_time

      # 檢查處理時間合理（每個簡訊不超過 0.5 秒）
      expect(processing_time).to be < 5.0
      expect(SmsLog.count).to eq(10)
      expect(SmsLog.sent.count).to eq(10)
    end
  end

  describe 'Rake Tasks Integration' do
    it 'executes daily reminder task successfully' do
      tomorrow = Date.current.tomorrow
      create(:reservation, :confirmed, restaurant: restaurant, reservation_datetime: tomorrow.beginning_of_day + 18.hours)

      # 模擬 rake 任務執行
      expect do
        DailyReminderJob.perform_now(tomorrow)
      end.to change(ActiveJob::Base.queue_adapter.enqueued_jobs, :count).by(1)
    end
  end
end
