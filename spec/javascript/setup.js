// Jest 測試設定檔案
// 設定 DOM 環境和全域 mocks

// 設定 global fetch mock
global.fetch = jest.fn();

// 設定 global console mock （可選，用於清理測試輸出）
global.console = {
  ...console,
  log: jest.fn(),
  error: jest.fn(),
  warn: jest.fn(),
  info: jest.fn(),
};

// 設定 global Date mock （確保測試結果一致）
const mockDate = new Date('2025-06-20T12:00:00Z');
jest.useFakeTimers('modern');
jest.setSystemTime(mockDate);

// DOM 設定
Object.defineProperty(window, 'location', {
  value: {
    href: 'http://localhost:3000',
    pathname: '/admin/restaurants/test/reservations/new',
    search: '',
    hash: '',
  },
  writable: true,
});

// 每個測試前清理 mocks
beforeEach(() => {
  fetch.mockClear();
  console.log.mockClear();
  console.error.mockClear();
  console.warn.mockClear();
  console.info.mockClear();
});

// 每個測試後清理 DOM
afterEach(() => {
  document.body.innerHTML = '';
});

// 全域測試後清理
afterAll(() => {
  jest.useRealTimers();
});