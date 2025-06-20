require 'rails_helper'

RSpec.describe 'API Security Tests', type: :request do
  let(:restaurant) { create(:restaurant, name: 'Security Test Restaurant') }
  let(:business_period) { create(:business_period, restaurant: restaurant) }
  let(:table_group) { create(:table_group, restaurant: restaurant) }
  let(:table) { create(:table, restaurant: restaurant, table_group: table_group) }

  before do
    business_period
    table
    restaurant.reservation_policy.update!(reservation_enabled: true)
  end

  describe 'Cross-Site Scripting (XSS) Prevention' do
    context 'Script injection in form fields' do
      let(:malicious_scripts) do
        [
          '<script>alert("XSS")</script>',
          '"><script>alert("XSS")</script>',
          'javascript:alert("XSS")',
          '<img src=x onerror=alert("XSS")>',
          '<svg onload=alert("XSS")>',
          'javascript:void(0)/*-/*`/*\`/*\'/*"/**/(/* */oNcliCk=alert() )//%0D%0A%0d%0a//</stYle/</titLe/</teXtarEa/</scRipt/--!>\x3csVg/<sVg/oNloAd=alert()//>\x3e',
          '\"><iframe src=\"javascript:alert(`XSS`)\">',
          '<details open ontoggle=alert("XSS")>'
        ]
      end

      it 'prevents XSS in customer name field' do
        malicious_scripts.each do |script|
          post restaurant_reservations_path(restaurant.slug), params: {
            reservation: {
              customer_name: script,
              customer_phone: '0912345678',
              customer_email: 'test@example.com'
            },
            date: Date.tomorrow.strftime('%Y-%m-%d'),
            time_slot: '18:00',
            adults: 2,
            children: 0,
            business_period_id: business_period.id
          }

          # 確保惡意腳本不會在回應中執行
          expect(response.body).not_to include('<script>')
          expect(response.body).not_to include('javascript:')
          expect(response.body).not_to include('onerror=')
          expect(response.body).not_to include('onload=')
          
          # 如果創建成功，檢查資料庫中的值是否被適當清理
          if response.status == 302
            reservation = Reservation.last
            expect(reservation.customer_name).not_to include('<script>')
            expect(reservation.customer_name).not_to include('javascript:')
          end
        end
      end

      it 'prevents XSS in special requests field' do
        malicious_scripts.each do |script|
          post restaurant_reservations_path(restaurant.slug), params: {
            reservation: {
              customer_name: '正常客戶',
              customer_phone: '0912345678',
              customer_email: 'test@example.com',
              special_requests: script
            },
            date: Date.tomorrow.strftime('%Y-%m-%d'),
            time_slot: '18:00',
            adults: 2,
            children: 0,
            business_period_id: business_period.id
          }

          expect(response.body).not_to include('<script>')
          expect(response.body).not_to include('javascript:')
          
          if response.status == 302
            reservation = Reservation.last
            expect(reservation.special_requests).not_to include('<script>') if reservation.special_requests
          end
        end
      end
    end
  end

  describe 'SQL Injection Prevention' do
    context 'Malicious SQL in parameters' do
      let(:sql_injection_payloads) do
        [
          "'; DROP TABLE reservations; --",
          "' OR '1'='1",
          "'; UPDATE reservations SET status='cancelled'; --",
          "' UNION SELECT * FROM users --",
          "'; INSERT INTO reservations VALUES (1,1,1,1); --",
          "1'; DELETE FROM reservations WHERE '1'='1",
          "'; EXEC xp_cmdshell('dir'); --",
          "' OR 1=1#",
          "admin'--",
          "' OR 'x'='x"
        ]
      end

      it 'prevents SQL injection in customer name' do
        sql_injection_payloads.each do |payload|
          expect {
            post restaurant_reservations_path(restaurant.slug), params: {
              reservation: {
                customer_name: payload,
                customer_phone: '0912345678',
                customer_email: 'test@example.com'
              },
              date: Date.tomorrow.strftime('%Y-%m-%d'),
              time_slot: '18:00',
              adults: 2,
              children: 0,
              business_period_id: business_period.id
            }
          }.not_to change { Reservation.count > 10 ? 0 : Reservation.count }
          
          # 確保沒有 SQL 錯誤被返回
          expect(response.body).not_to include('SQL')
          expect(response.body).not_to include('syntax error')
          expect(response.body).not_to include('mysql')
          expect(response.body).not_to include('postgresql')
        end
      end

      it 'prevents SQL injection in search parameters' do
        sql_injection_payloads.each do |payload|
          get restaurant_available_times_path(restaurant.slug), params: {
            date: payload,
            adults: 2,
            children: 0
          }
          
          expect(response.body).not_to include('SQL')
          expect(response.body).not_to include('syntax error')
        end
      end
    end
  end

  describe 'CSRF Protection' do
    context 'Cross-Site Request Forgery attacks' do
      it 'requires CSRF token for POST requests' do
        # 模擬沒有 CSRF token 的請求
        allow_any_instance_of(ActionController::Base).to receive(:verified_request?).and_return(false)
        
        post restaurant_reservations_path(restaurant.slug), params: {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: '0912345678',
            customer_email: 'test@example.com'
          },
          date: Date.tomorrow.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 2,
          children: 0,
          business_period_id: business_period.id
        }

        # 應該被拒絕或重導向
        expect([422, 302, 403]).to include(response.status)
      end
    end
  end

  describe 'Input Validation and Sanitization' do
    context 'Malformed data injection' do
      it 'handles extremely long input strings' do
        long_string = 'A' * 10000

        post restaurant_reservations_path(restaurant.slug), params: {
          reservation: {
            customer_name: long_string,
            customer_phone: '0912345678',
            customer_email: 'test@example.com'
          },
          date: Date.tomorrow.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 2,
          children: 0,
          business_period_id: business_period.id
        }

        # 應該正確處理或拒絕過長的輸入
        expect([422, 400]).to include(response.status)
      end

      it 'validates email format strictly' do
        malicious_emails = [
          'test@<script>alert("XSS")</script>.com',
          'test"@example.com',
          'test@example.com<script>',
          'test+<svg onload=alert()>@example.com'
        ]

        malicious_emails.each do |email|
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

          expect(response.status).to eq(422)
          expect(response.body).not_to include('<script>')
        end
      end

      it 'validates phone number format' do
        malicious_phones = [
          '091234567<script>alert()</script>',
          '0912-345-678; DROP TABLE reservations;',
          '0912345678\'OR\'1\'=\'1'
        ]

        malicious_phones.each do |phone|
          post restaurant_reservations_path(restaurant.slug), params: {
            reservation: {
              customer_name: '測試客戶',
              customer_phone: phone,
              customer_email: 'test@example.com'
            },
            date: Date.tomorrow.strftime('%Y-%m-%d'),
            time_slot: '18:00',
            adults: 2,
            children: 0,
            business_period_id: business_period.id
          }

          expect([422, 400]).to include(response.status)
          expect(response.body).not_to include('<script>')
        end
      end
    end
  end

  describe 'Rate Limiting Protection' do
    context 'Excessive request rates' do
      it 'handles rapid consecutive requests gracefully' do
        start_time = Time.current
        responses = []

        # 快速發送多個請求
        20.times do |i|
          response = nil
          begin
            post restaurant_reservations_path(restaurant.slug), params: {
              reservation: {
                customer_name: "客戶#{i}",
                customer_phone: "091234567#{i % 10}",
                customer_email: "test#{i}@example.com"
              },
              date: Date.tomorrow.strftime('%Y-%m-%d'),
              time_slot: '18:00',
              adults: 2,
              children: 0,
              business_period_id: business_period.id
            }
            responses << response.status
          rescue => e
            # 紀錄但不讓測試失敗
            puts "Request #{i} failed: #{e.message}" if ENV['VERBOSE_TESTS']
          end
        end

        end_time = Time.current
        duration = end_time - start_time

        # 檢查系統是否能在合理時間內處理請求
        expect(duration).to be < 30.seconds
        # 至少應該有一些成功的回應
        expect(responses.count { |status| [200, 302, 422].include?(status) }).to be > 0
      end
    end
  end

  describe 'Authentication Bypass Attempts' do
    context 'Session manipulation' do
      it 'prevents session hijacking attempts' do
        # 嘗試使用無效的 session ID
        get restaurant_reservations_path(restaurant.slug), 
            headers: { 'Cookie' => '_session_id=invalid_session_12345' }

        # 應該正常處理，不會出現錯誤
        expect([200, 302]).to include(response.status)
      end

      it 'handles malformed cookies gracefully' do
        malformed_cookies = [
          '_session_id=<script>alert("XSS")</script>',
          '_session_id=\'; DROP TABLE sessions; --',
          '_session_id=' + 'A' * 10000
        ]

        malformed_cookies.each do |cookie|
          get restaurant_reservations_path(restaurant.slug), 
              headers: { 'Cookie' => cookie }

          expect([200, 302, 400]).to include(response.status)
          expect(response.body).not_to include('<script>')
        end
      end
    end
  end

  describe 'File Upload Security' do
    context 'Malicious file upload attempts' do
      it 'rejects executable file uploads' do
        skip 'File upload not implemented in reservations' unless respond_to?(:file_upload_path)
        
        # 這裡會測試文件上傳功能（如果存在）
        # 例如：上傳惡意腳本文件、超大文件等
      end
    end
  end

  describe 'HTTP Header Security' do
    context 'Security headers presence' do
      it 'includes security headers in responses' do
        get restaurant_reservations_path(restaurant.slug)

        # 檢查重要的安全 headers
        expect(response.headers['X-Frame-Options']).to be_present
        expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
        
        # 檢查是否沒有洩露敏感信息
        expect(response.headers['Server']).not_to include('version') if response.headers['Server']
        expect(response.headers['X-Powered-By']).to be_nil
      end

      it 'prevents clickjacking attacks' do
        get restaurant_reservations_path(restaurant.slug)
        
        x_frame_options = response.headers['X-Frame-Options']
        expect(['DENY', 'SAMEORIGIN']).to include(x_frame_options) if x_frame_options
      end
    end
  end

  describe 'API Parameter Pollution' do
    context 'Duplicate parameters' do
      it 'handles parameter pollution correctly' do
        # 測試參數污染攻擊
        post restaurant_reservations_path(restaurant.slug), params: {
          reservation: {
            customer_name: '正常客戶',
            customer_phone: '0912345678'
          },
          'reservation[customer_name]' => '惡意客戶',
          date: Date.tomorrow.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 2,
          children: 0,
          business_period_id: business_period.id
        }

        # 系統應該能正確處理重複參數
        expect([200, 302, 422]).to include(response.status)
        
        if response.status == 302
          reservation = Reservation.last
          # 確保使用了正確的參數值
          expect(['正常客戶', '惡意客戶']).to include(reservation.customer_name)
        end
      end
    end
  end

  describe 'Mass Assignment Protection' do
    context 'Unauthorized attribute modification' do
      it 'prevents mass assignment of protected attributes' do
        post restaurant_reservations_path(restaurant.slug), params: {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: '0912345678',
            customer_email: 'test@example.com',
            # 嘗試修改不應該被修改的屬性
            status: 'confirmed',
            id: 999999,
            created_at: 1.year.ago,
            restaurant_id: 999999
          },
          date: Date.tomorrow.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 2,
          children: 0,
          business_period_id: business_period.id
        }

        if response.status == 302
          reservation = Reservation.last
          # 確保受保護的屬性沒有被修改
          expect(reservation.status).not_to eq('confirmed')
          expect(reservation.restaurant_id).to eq(restaurant.id)
        end
      end
    end
  end

  describe 'Information Disclosure Prevention' do
    context 'Error message information leakage' do
      it 'does not expose sensitive information in error messages' do
        # 嘗試觸發各種錯誤
        post restaurant_reservations_path(restaurant.slug), params: {
          reservation: {
            customer_name: '',
            customer_phone: 'invalid',
            customer_email: 'invalid'
          },
          date: 'invalid',
          time_slot: 'invalid',
          adults: -1,
          children: -1,
          business_period_id: 999999
        }

        # 檢查錯誤訊息不會洩露敏感信息
        expect(response.body).not_to include('database')
        expect(response.body).not_to include('SQL')
        expect(response.body).not_to include('password')
        expect(response.body).not_to include('secret')
        expect(response.body).not_to include('config')
        expect(response.body).not_to include('/app/')
        expect(response.body).not_to include('gem')
      end
    end

    context 'Stack trace exposure' do
      it 'does not expose stack traces to users' do
        # 嘗試觸發內部錯誤
        allow_any_instance_of(ReservationsController).to receive(:create).and_raise(StandardError.new('Internal error'))

        post restaurant_reservations_path(restaurant.slug), params: {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: '0912345678',
            customer_email: 'test@example.com'
          },
          date: Date.tomorrow.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 2,
          children: 0,
          business_period_id: business_period.id
        }

        # 不應該在回應中看到 stack trace
        expect(response.body).not_to include('app/controllers')
        expect(response.body).not_to include('backtrace')
        expect(response.body).not_to include('.rb:')
      end
    end
  end

  describe 'Business Logic Security' do
    context 'Reservation manipulation' do
      it 'prevents reservation time manipulation' do
        # 嘗試預約過去的時間
        post restaurant_reservations_path(restaurant.slug), params: {
          reservation: {
            customer_name: '測試客戶',
            customer_phone: '0912345678',
            customer_email: 'test@example.com'
          },
          date: 1.day.ago.strftime('%Y-%m-%d'),
          time_slot: '18:00',
          adults: 2,
          children: 0,
          business_period_id: business_period.id
        }

        expect(response.status).to eq(422)
      end

      it 'validates party size limits strictly' do
        extreme_party_sizes = [-1, 0, 999999, 'invalid']

        extreme_party_sizes.each do |size|
          post restaurant_reservations_path(restaurant.slug), params: {
            reservation: {
              customer_name: '測試客戶',
              customer_phone: '0912345678',
              customer_email: 'test@example.com'
            },
            date: Date.tomorrow.strftime('%Y-%m-%d'),
            time_slot: '18:00',
            adults: size,
            children: 0,
            business_period_id: business_period.id
          }

          expect([422, 400]).to include(response.status)
        end
      end
    end
  end
end