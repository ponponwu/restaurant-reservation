require 'rails_helper'

RSpec.describe SmsService, type: :service do
  let(:restaurant) { create(:restaurant, name: '測試餐廳', phone: '02-12345678') }
  let(:reservation) { create(:reservation, restaurant: restaurant, customer_name: '張三', customer_phone: '0912345678') }
  let(:sms_service) { described_class.new }

  before do
    # 設定測試環境變數
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SMS_SERVICE_ENABLED').and_return('true')
    allow(ENV).to receive(:[]).with('SMS_SERVICE_URL').and_return('https://api.example.com/sms')
    allow(ENV).to receive(:[]).with('SMS_SERVICE_API_KEY').and_return('test-api-key')
    allow(ENV).to receive(:[]).with('SMS_SERVICE_FROM').and_return('測試餐廳')
    allow(ENV).to receive(:[]).with('SMS_SERVICE_TIMEOUT').and_return('30')
  end

  describe '#send_reservation_confirmation' do
    context 'when SMS service is enabled' do
      it 'sends confirmation SMS successfully' do
        result = sms_service.send_reservation_confirmation(reservation)

        expect(result[:success]).to be true
        expect(result[:sms_log]).to be_a(SmsLog)
        expect(result[:sms_log].message_type).to eq('reservation_confirmation')
        expect(result[:sms_log].status).to eq('sent')
        expect(result[:sms_log].phone_number).to eq('0912345678')
      end

      it 'creates SMS log with correct content' do
        result = sms_service.send_reservation_confirmation(reservation)

        sms_log = result[:sms_log]
        expect(sms_log.content).to include('測試餐廳 訂位確認')
        expect(sms_log.content).to include('張三')
        expect(sms_log.content).to include('02-12345678')
        expect(sms_log.content).to include('期待您的光臨！🌟')
      end
    end

    context 'when SMS service is disabled' do
      before do
        allow(ENV).to receive(:[]).with('SMS_SERVICE_ENABLED').and_return('false')
      end

      it 'returns failure result' do
        result = sms_service.send_reservation_confirmation(reservation)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('SMS service disabled')
      end
    end
  end

  describe '#send_dining_reminder' do
    it 'sends reminder SMS successfully' do
      result = sms_service.send_dining_reminder(reservation)

      expect(result[:success]).to be true
      expect(result[:sms_log]).to be_a(SmsLog)
      expect(result[:sms_log].message_type).to eq('dining_reminder')
      expect(result[:sms_log].status).to eq('sent')
    end

    it 'creates SMS log with reminder content' do
      result = sms_service.send_dining_reminder(reservation)

      sms_log = result[:sms_log]
      expect(sms_log.content).to include('用餐提醒')
      expect(sms_log.content).to include('提醒您明天的用餐時間')
      expect(sms_log.content).to include('張三')
    end
  end

  describe '#send_reservation_cancellation' do
    let(:cancellation_reason) { '客戶主動取消' }

    it 'sends cancellation SMS successfully' do
      result = sms_service.send_reservation_cancellation(reservation, cancellation_reason)

      expect(result[:success]).to be true
      expect(result[:sms_log]).to be_a(SmsLog)
      expect(result[:sms_log].message_type).to eq('reservation_cancellation')
      expect(result[:sms_log].status).to eq('sent')
    end

    it 'includes cancellation reason in message' do
      result = sms_service.send_reservation_cancellation(reservation, cancellation_reason)

      sms_log = result[:sms_log]
      expect(sms_log.content).to include('訂位取消')
      expect(sms_log.content).to include(cancellation_reason)
    end
  end

  describe 'error handling' do
    it 'handles missing phone number' do
      reservation.update(customer_phone: '')
      result = sms_service.send_reservation_confirmation(reservation)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Missing required parameters')
    end

    it 'handles SMS service errors' do
      # 模擬 HTTP 錯誤
      mock_response = Object.new
      mock_response.define_singleton_method(:code) { '500' }
      mock_response.define_singleton_method(:body) { 'Internal Server Error' }

      allow(sms_service).to receive(:send_http_request).and_return(mock_response)

      result = sms_service.send_reservation_confirmation(reservation)

      expect(result[:success]).to be false
      expect(result[:error]).to include('SMS sending failed')
      expect(result[:sms_log].status).to eq('failed')
    end
  end

  describe 'message formatting' do
    it 'formats confirmation message correctly' do
      result = sms_service.send_reservation_confirmation(reservation)
      content = result[:sms_log].content

      expect(content).to include('🍽️')
      expect(content).to include('━━━━━━━━━━━━━━━━━━━━')
      expect(content).to include('👤 訂位人：張三')
      expect(content).to include('📅 用餐時間：')
      expect(content).to include('👥 用餐人數：')
      expect(content).to include('🪑 桌位：')
      expect(content).to include('📞 如需異動或取消，請撥打：02-12345678')
    end

    it 'includes special requests in confirmation message' do
      reservation.update(special_requests: '素食')
      result = sms_service.send_reservation_confirmation(reservation)

      expect(result[:sms_log].content).to include('📝 特殊要求：素食')
    end

    it 'includes children count in confirmation message' do
      reservation.update(children_count: 2)
      result = sms_service.send_reservation_confirmation(reservation)

      expect(result[:sms_log].content).to include('(含兒童 2人)')
    end
  end
end
