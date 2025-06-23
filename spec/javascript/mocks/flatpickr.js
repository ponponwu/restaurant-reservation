// Flatpickr Mock
const mockFlatpickrInstance = {
  destroy: jest.fn(),
  set: jest.fn(),
  redraw: jest.fn(),
  setDate: jest.fn(),
  clear: jest.fn(),
  open: jest.fn(),
  close: jest.fn(),
};

const mockFlatpickr = jest.fn(() => mockFlatpickrInstance);

// 模擬靜態方法
mockFlatpickr.localize = jest.fn();
mockFlatpickr.formatDate = jest.fn();
mockFlatpickr.parseDate = jest.fn();

// 模擬語言包
mockFlatpickr.l10ns = {
  zh_tw: {
    weekdays: {
      shorthand: ['日', '一', '二', '三', '四', '五', '六'],
      longhand: ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']
    },
    months: {
      shorthand: ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'],
      longhand: ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月']
    }
  }
};

module.exports = mockFlatpickr;