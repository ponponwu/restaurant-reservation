FactoryBot.define do
  factory :sms_log do
    association :reservation
    phone_number { '0912345678' }
    message_type { 'reservation_confirmation' }
    content { "【測試餐廳】訂位確認\n訂位人：張三\n用餐時間：2024-01-15 18:00\n人數：2人" }
    status { 'pending' }
    response_data { nil }

    trait :sent do
      status { 'sent' }
      response_data { { status: 'sent', id: 'sms-123' }.to_json }
    end

    trait :failed do
      status { 'failed' }
      response_data { { error: 'Invalid phone number' }.to_json }
    end

    trait :error do
      status { 'error' }
      response_data { 'Network timeout' }
    end

    trait :confirmation do
      message_type { 'reservation_confirmation' }
      content { "🍽️ 測試餐廳 訂位確認\n━━━━━━━━━━━━━━━━━━━━\n👤 訂位人：張三\n📅 用餐時間：2024/01/15 18:00\n👥 用餐人數：2人\n🪑 桌位：1號桌\n━━━━━━━━━━━━━━━━━━━━\n📞 如需異動或取消，請撥打：02-12345678\n\n期待您的光臨！🌟" }
    end

    trait :reminder do
      message_type { 'dining_reminder' }
      content { "⏰ 測試餐廳 用餐提醒\n━━━━━━━━━━━━━━━━━━━━\n👤 張三 您好，\n提醒您明天的用餐時間：\n\n📅 日期：2024/01/15\n⏰ 時間：18:00\n👥 人數：2人\n🪑 桌位：1號桌\n━━━━━━━━━━━━━━━━━━━━\n📞 電話：02-12345678\n\n期待您的光臨！🌟" }
    end

    trait :cancellation do
      message_type { 'reservation_cancellation' }
      content { "❌ 測試餐廳 訂位取消\n━━━━━━━━━━━━━━━━━━━━\n👤 張三 您好，\n您的訂位已取消：\n\n📅 日期：2024/01/15\n⏰ 時間：18:00\n👥 人數：2人\n━━━━━━━━━━━━━━━━━━━━\n如有任何問題，請聯繫餐廳：\n📞 電話：02-12345678\n\n感謝您的使用！" }
    end
  end
end
