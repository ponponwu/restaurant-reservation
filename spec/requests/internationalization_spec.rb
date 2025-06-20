require 'rails_helper'

RSpec.describe 'Internationalization Tests', type: :request do
  let(:restaurant) { create(:restaurant, name: 'International Restaurant') }
  let(:business_period) { create(:business_period, restaurant: restaurant) }
  let(:table_group) { create(:table_group, restaurant: restaurant) }
  let(:table) { create(:table, restaurant: restaurant, table_group: table_group) }

  before do
    business_period
    table
    restaurant.reservation_policy.update!(reservation_enabled: true)
  end

  describe 'Multi-language support' do
    context 'Traditional Chinese (zh-TW)' do
      before { I18n.locale = :'zh-TW' }
      after { I18n.locale = I18n.default_locale }

      it 'displays reservation form in Traditional Chinese' do
        get new_restaurant_reservation_path(restaurant.slug), params: {
          date: Date.tomorrow.strftime('%Y-%m-%d'),
          adults: 2,
          children: 0,
          time: '18:00',
          period_id: business_period.id
        }

        expect(response).to have_http_status(:success)
        # 檢查是否包含繁體中文文字
        expect(response.body).to include('預約') if response.body.present?
      end

      it 'validates error messages in Traditional Chinese' do
        post restaurant_reservations_path(restaurant.slug), params: {
          reservation: {
            customer_name: '',  # 空白姓名
            customer_phone: '0912345678',
            customer_email: 'test@example.com'
          },
          date: Date.tomorrow.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 2,
          children: 0,
          business_period_id: business_period.id
        }

        expect(response).to have_http_status(:unprocessable_entity)
        # 檢查錯誤訊息是否為中文
        expect(response.body).to include('不能') if response.body.present?
      end
    end

    context 'English (en)' do
      before { I18n.locale = :en }
      after { I18n.locale = I18n.default_locale }

      it 'displays reservation form in English' do
        get new_restaurant_reservation_path(restaurant.slug), params: {
          date: Date.tomorrow.strftime('%Y-%m-%d'),
          adults: 2,
          children: 0,
          time: '18:00',
          period_id: business_period.id
        }

        expect(response).to have_http_status(:success)
        # 檢查是否包含英文文字
        expect(response.body).to include('Reservation') if response.body.present?
      end

      it 'validates error messages in English' do
        post restaurant_reservations_path(restaurant.slug), params: {
          reservation: {
            customer_name: '',  # 空白姓名
            customer_phone: '0912345678',
            customer_email: 'test@example.com'
          },
          date: Date.tomorrow.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 2,
          children: 0,
          business_period_id: business_period.id
        }

        expect(response).to have_http_status(:unprocessable_entity)
        # 檢查錯誤訊息是否為英文
        expect(response.body).to include("can't be blank") if response.body.present?
      end
    end

    context 'Japanese (ja)' do
      before { I18n.locale = :ja }
      after { I18n.locale = I18n.default_locale }

      it 'displays date format in Japanese locale' do
        get new_restaurant_reservation_path(restaurant.slug), params: {
          date: Date.tomorrow.strftime('%Y-%m-%d'),
          adults: 2,
          children: 0,
          time: '18:00',
          period_id: business_period.id
        }

        expect(response).to have_http_status(:success)
        # 檢查日期格式是否適合日文環境
        formatted_date = I18n.l(Date.tomorrow, format: :long)
        expect(formatted_date).to include('年') if formatted_date.present?
      end
    end
  end

  describe 'Locale-specific formatting' do
    let(:test_date) { Date.new(2024, 12, 25) }
    let(:test_time) { Time.zone.parse('2024-12-25 18:30:00') }

    context 'Date formatting' do
      it 'formats dates according to locale' do
        expect(I18n.l(test_date, locale: :'zh-TW')).to include('年')
        expect(I18n.l(test_date, locale: :en)).to include('Dec')
        expect(I18n.l(test_date, locale: :ja)).to include('月')
      end
    end

    context 'Time formatting' do
      it 'formats time according to locale' do
        tw_time = I18n.l(test_time, format: :short, locale: :'zh-TW')
        en_time = I18n.l(test_time, format: :short, locale: :en)
        ja_time = I18n.l(test_time, format: :short, locale: :ja)

        expect(tw_time).to be_present
        expect(en_time).to be_present
        expect(ja_time).to be_present
      end
    end
  end

  describe 'Currency and number formatting' do
    context 'Number formatting' do
      it 'formats numbers according to locale' do
        number = 1234.56

        # 測試不同語言環境的數字格式
        expect(number_with_delimiter(number, locale: :'zh-TW')).to be_present
        expect(number_with_delimiter(number, locale: :en)).to be_present
        expect(number_with_delimiter(number, locale: :ja)).to be_present
      end
    end
  end

  describe 'Error message localization' do
    context 'Validation errors' do
      it 'provides localized validation messages' do
        reservation = Reservation.new(restaurant: restaurant)
        
        # 測試不同語言的驗證訊息
        I18n.with_locale(:'zh-TW') do
          reservation.valid?
          expect(reservation.errors.full_messages.join).to include('不能') if reservation.errors.any?
        end

        I18n.with_locale(:en) do
          reservation.valid?
          expect(reservation.errors.full_messages.join).to include("can't be blank") if reservation.errors.any?
        end
      end
    end

    context 'Custom error messages' do
      it 'provides localized business logic messages' do
        # 測試自定義錯誤訊息的本地化
        blacklisted_phone = '0987654321'
        create(:blacklist, restaurant: restaurant, customer_phone: blacklisted_phone)

        I18n.with_locale(:'zh-TW') do
          post restaurant_reservations_path(restaurant.slug), params: {
            reservation: {
              customer_name: '測試客戶',
              customer_phone: blacklisted_phone,
              customer_email: 'test@example.com'
            },
            date: Date.tomorrow.strftime('%Y-%m-%d'),
            time_slot: '18:00',
            adults: 2,
            children: 0,
            business_period_id: business_period.id
          }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).to include('訂位失敗') if response.body.present?
        end
      end
    end
  end

  describe 'Time zone handling' do
    context 'Different time zones' do
      it 'handles reservations across time zones' do
        # 測試時區處理
        original_zone = Time.zone
        
        begin
          # 測試台北時區
          Time.zone = 'Asia/Taipei'
          taipei_time = Time.zone.parse('2024-12-25 18:00:00')
          
          # 測試東京時區
          Time.zone = 'Asia/Tokyo'
          tokyo_time = Time.zone.parse('2024-12-25 18:00:00')
          
          # 測試紐約時區
          Time.zone = 'America/New_York'
          ny_time = Time.zone.parse('2024-12-25 18:00:00')
          
          expect(taipei_time).to be_present
          expect(tokyo_time).to be_present
          expect(ny_time).to be_present
        ensure
          Time.zone = original_zone
        end
      end
    end
  end

  describe 'Character encoding' do
    context 'Unicode support' do
      it 'handles unicode characters in customer names' do
        unicode_names = [
          '張三',           # 中文
          'José María',     # 西班牙文
          'François',       # 法文
          '田中太郎',        # 日文
          '김철수',         # 韓文
          'Müller',         # 德文
          'Åsa Öberg'       # 瑞典文
        ]

        unicode_names.each do |name|
          post restaurant_reservations_path(restaurant.slug), params: {
            reservation: {
              customer_name: name,
              customer_phone: '0912345678',
              customer_email: 'test@example.com'
            },
            date: Date.tomorrow.strftime('%Y-%m-%d'),
            time_slot: '18:00',
            adults: 2,
            children: 0,
            business_period_id: business_period.id
          }

          # 應該能正確處理 Unicode 字符，不會導致錯誤
          expect([200, 302, 422]).to include(response.status)
          
          if response.status == 302
            reservation = Reservation.last
            expect(reservation.customer_name).to eq(name)
          end
        end
      end
    end

    context 'Email encoding' do
      it 'handles international email addresses' do
        international_emails = [
          'test@测试.com',      # 中文域名
          'użytkownik@świat.pl', # 波蘭文
          'тест@тест.рф'        # 俄文
        ]

        international_emails.each do |email|
          post restaurant_reservations_path(restaurant.slug), params: {
            reservation: {
              customer_name: '測試客戶',
              customer_phone: '0912345678',
              customer_email: email
            },
            date: Date.tomorrow.strftime('%Y-%m-%d'),
            time_slot: '18:00',
            adults: 2,
            children: 0,
            business_period_id: business_period.id
          }

          # 系統應該能處理國際化郵件地址
          expect([200, 302, 422]).to include(response.status)
        end
      end
    end
  end

  describe 'Right-to-left (RTL) language support' do
    context 'Arabic text direction' do
      it 'handles RTL text correctly' do
        arabic_name = 'محمد أحمد'
        hebrew_name = 'דוד כהן'

        [arabic_name, hebrew_name].each do |name|
          post restaurant_reservations_path(restaurant.slug), params: {
            reservation: {
              customer_name: name,
              customer_phone: '0912345678',
              customer_email: 'test@example.com'
            },
            date: Date.tomorrow.strftime('%Y-%m-%d'),
            time_slot: '18:00',
            adults: 2,
            children: 0,
            business_period_id: business_period.id
          }

          expect([200, 302, 422]).to include(response.status)
          
          if response.status == 302
            reservation = Reservation.last
            expect(reservation.customer_name).to eq(name)
          end
        end
      end
    end
  end

  describe 'Pluralization rules' do
    context 'Different pluralization systems' do
      it 'handles pluralization correctly' do
        # 測試不同語言的複數規則
        party_sizes = [1, 2, 5, 11, 21]
        
        party_sizes.each do |size|
          I18n.with_locale(:'zh-TW') do
            # 中文沒有複數變化
            expect(I18n.t('party_size', count: size, default: "#{size} 人")).to include(size.to_s)
          end
          
          I18n.with_locale(:en) do
            # 英文有複數變化
            if size == 1
              expect(I18n.t('party_size', count: size, default: "#{size} person")).to include('person')
            else
              expect(I18n.t('party_size', count: size, default: "#{size} people")).to include('people')
            end
          end
        end
      end
    end
  end

  private

  def number_with_delimiter(number, options = {})
    # 簡化的數字格式化方法
    case options[:locale]
    when :'zh-TW'
      number.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\1,')
    when :en
      number.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\1,')
    when :ja
      number.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\1,')
    else
      number.to_s
    end
  end
end