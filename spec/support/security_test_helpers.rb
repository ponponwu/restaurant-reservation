module SecurityTestHelpers
  # XSS 攻擊向量
  XSS_PAYLOADS = [
    '<script>alert("XSS")</script>',
    '"><script>alert("XSS")</script>',
    'javascript:alert("XSS")',
    '<img src=x onerror=alert("XSS")>',
    '<svg onload=alert("XSS")>',
    '<iframe src="javascript:alert(\'XSS\')">',
    '<details open ontoggle=alert("XSS")>',
    '<input type="text" onfocus="alert(\'XSS\')" autofocus>',
    '<body onload=alert("XSS")>',
    '<div onclick="alert(\'XSS\')">Click me</div>'
  ].freeze

  # SQL 注入攻擊向量
  SQL_INJECTION_PAYLOADS = [
    "'; DROP TABLE reservations; --",
    "' OR '1'='1",
    "'; UPDATE reservations SET status='cancelled'; --",
    "' UNION SELECT * FROM users --",
    "'; INSERT INTO reservations VALUES (1,1,1,1); --",
    "1'; DELETE FROM reservations WHERE '1'='1",
    "'; EXEC xp_cmdshell('dir'); --",
    "' OR 1=1#",
    "admin'--",
    "' OR 'x'='x",
    "1' AND SLEEP(5)--",
    "'; WAITFOR DELAY '00:00:05'--"
  ].freeze

  # 惡意郵件地址
  MALICIOUS_EMAILS = [
    'test@<script>alert("XSS")</script>.com',
    'test"@example.com',
    'test@example.com<script>',
    'test+<svg onload=alert()>@example.com',
    'test@example.com"; DROP TABLE users; --',
    "test@example.com'; OR '1'='1"
  ].freeze

  # 惡意電話號碼
  MALICIOUS_PHONES = [
    '091234567<script>alert()</script>',
    '0912-345-678; DROP TABLE reservations;',
    '0912345678\'OR\'1\'=\'1',
    '0912345678"; DELETE FROM reservations; --'
  ].freeze

  # 超長字串攻擊
  OVERSIZED_STRINGS = [
    'A' * 1000,    # 1KB
    'A' * 10000,   # 10KB  
    'A' * 100000,  # 100KB
    '中文字符' * 2500  # Unicode 長字串
  ].freeze

  # HTTP Header 注入攻擊
  HEADER_INJECTION_PAYLOADS = [
    "test\r\nX-Injected-Header: malicious",
    "test\nLocation: http://evil.com",
    "test\r\nSet-Cookie: admin=true"
  ].freeze

  # 檢查回應是否包含 XSS 痕跡
  def assert_no_xss(response_body)
    expect(response_body).not_to include('<script>')
    expect(response_body).not_to include('javascript:')
    expect(response_body).not_to include('onerror=')
    expect(response_body).not_to include('onload=')
    expect(response_body).not_to include('onfocus=')
    expect(response_body).not_to include('onclick=')
    expect(response_body).not_to include('<iframe')
    expect(response_body).not_to include('<object')
    expect(response_body).not_to include('<embed')
  end

  # 檢查回應是否包含 SQL 錯誤痕跡
  def assert_no_sql_errors(response_body)
    expect(response_body).not_to include('SQL')
    expect(response_body).not_to include('syntax error')
    expect(response_body).not_to include('mysql')
    expect(response_body).not_to include('postgresql')
    expect(response_body).not_to include('sqlite')
    expect(response_body).not_to include('ORA-')
    expect(response_body).not_to include('ERROR 1064')
  end

  # 檢查回應是否洩露敏感信息
  def assert_no_information_disclosure(response_body)
    expect(response_body).not_to include('database')
    expect(response_body).not_to include('password')
    expect(response_body).not_to include('secret')
    expect(response_body).not_to include('config')
    expect(response_body).not_to include('/app/')
    expect(response_body).not_to include('gem')
    expect(response_body).not_to include('backtrace')
    expect(response_body).not_to include('.rb:')
    expect(response_body).not_to include('app/controllers')
  end

  # 檢查安全 Headers
  def assert_security_headers(response_headers)
    # X-Frame-Options 防止 Clickjacking
    expect(['DENY', 'SAMEORIGIN']).to include(response_headers['X-Frame-Options']) if response_headers['X-Frame-Options']
    
    # X-Content-Type-Options 防止 MIME 類型混淆
    expect(response_headers['X-Content-Type-Options']).to eq('nosniff') if response_headers['X-Content-Type-Options']
    
    # X-XSS-Protection 啟用瀏覽器 XSS 過濾
    expect(response_headers['X-XSS-Protection']).to be_present if response_headers['X-XSS-Protection']
    
    # 不應該洩露服務器版本信息
    expect(response_headers['Server']).not_to include('version') if response_headers['Server']
    expect(response_headers['X-Powered-By']).to be_nil
  end

  # 測試參數污染
  def test_parameter_pollution(base_params, polluted_key, original_value, malicious_value)
    params_with_pollution = base_params.dup
    params_with_pollution[polluted_key] = original_value
    params_with_pollution["#{polluted_key}_malicious"] = malicious_value
    params_with_pollution
  end

  # 生成隨機惡意負載
  def random_xss_payload
    XSS_PAYLOADS.sample
  end

  def random_sql_injection_payload
    SQL_INJECTION_PAYLOADS.sample
  end

  # 測試並發請求安全性
  def test_concurrent_requests(url, params_generator, count = 10)
    threads = []
    results = []
    
    count.times do |i|
      threads << Thread.new do
        begin
          params = params_generator.call(i)
          # 這里需要根據實際的測試框架調整
          response = make_request(url, params)
          results << response
        rescue => e
          results << { error: e.message }
        end
      end
    end
    
    threads.each(&:join)
    results
  end

  # 檢查速率限制
  def assert_rate_limiting(responses)
    status_codes = responses.map { |r| r.is_a?(Hash) && r[:error] ? 500 : r.status }
    
    # 至少應該有一些請求被限制或正常處理
    expect(status_codes.count { |code| [200, 302, 422, 429].include?(code) }).to be > 0
    
    # 不應該全部都是錯誤
    expect(status_codes.count { |code| code >= 500 }).to be < responses.length
  end

  # Unicode 安全測試
  def unicode_security_test_strings
    [
      '测试用户名',           # 簡體中文
      '測試用戶名',           # 繁體中文  
      'テストユーザー',        # 日文
      '테스트사용자',          # 韓文
      'тестовое имя',        # 俄文
      'اسم المستخدم',        # 阿拉伯文
      'שם משתמש',            # 希伯來文
      'ü̈n̈ï̈c̈ö̈d̈ë̈',          # 組合字符
      '💀💻🔒',              # Emoji
      "\u0000\u0001\u0002",  # 控制字符
      "A\u034F\u034F\u034FB", # 零寬字符
    ]
  end

  # 邊界值測試
  def boundary_test_values
    {
      integers: [-2147483648, -1, 0, 1, 2147483647, 2147483648],
      strings: ['', 'a', 'A' * 255, 'A' * 256, 'A' * 1000],
      floats: [-999999.99, -0.01, 0.0, 0.01, 999999.99],
      dates: ['1900-01-01', '2000-02-29', '2038-01-19', '9999-12-31'],
      emails: ['a@b.c', 'test@' + 'a' * 250 + '.com'],
      phones: ['1', '12345678901234567890']
    }
  end

  private

  # 輔助方法：發送請求（需要根據測試框架調整）
  def make_request(url, params)
    # 這裡需要實現實際的 HTTP 請求邏輯
    # 在 RSpec 中可能是 post, get 等方法
    raise NotImplementedError, "Implement make_request for your testing framework"
  end
end

# 在 RSpec 中包含這個模組
RSpec.configure do |config|
  config.include SecurityTestHelpers, type: :request
end