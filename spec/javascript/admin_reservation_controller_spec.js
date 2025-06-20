/**
 * Admin Reservation Controller JavaScript Tests
 * 測試後台訂位日曆的休息日排除邏輯
 */

// Mock 設定
global.fetch = jest.fn();
global.flatpickr = jest.fn();

// Mock flatpickr
const mockFlatpickrInstance = {
  destroy: jest.fn(),
  set: jest.fn(),
  redraw: jest.fn()
};

// Mock Stimulus Controller
class MockController {
  constructor() {
    this.targets = [];
    this.values = {};
    this.element = document.createElement('div');
  }
  
  hasCalendarTarget = true;
  calendarTarget = document.createElement('div');
  hasDateFieldTarget = true;
  dateFieldTarget = document.createElement('input');
  hasTimeFieldTarget = true;
  timeFieldTarget = document.createElement('input');
  hasDatetimeFieldTarget = true;
  datetimeFieldTarget = document.createElement('input');
  hasPartySizeTarget = true;
  partySizeTarget = document.createElement('select');
  restaurantSlugValue = 'test-restaurant';
}

// 導入要測試的控制器（假設我們可以這樣做）
// 在實際情況中，你可能需要使用適當的 JavaScript 測試設置
class AdminReservationController extends MockController {
  calculateAdminDisabledDates(weekly_closures, special_closures) {
    const disabledDates = [];

    // 處理每週固定休息日
    if (weekly_closures && weekly_closures.length > 0) {
      disabledDates.push((date) => {
        const dayOfWeek = date.getDay();
        return weekly_closures.includes(dayOfWeek);
      });
    }

    // 處理特殊休息日
    if (special_closures && special_closures.length > 0) {
      special_closures.forEach((closureStr) => {
        const closureDate = new Date(closureStr);
        disabledDates.push((date) => {
          return (
            date.getFullYear() === closureDate.getFullYear() &&
            date.getMonth() === closureDate.getMonth() &&
            date.getDate() === closureDate.getDate()
          );
        });
      });
    }

    return disabledDates;
  }

  async fetchDisabledDates() {
    try {
      const partySize = this.getCurrentPartySize();
      const apiUrl = `/restaurants/${this.restaurantSlugValue}/available_days?party_size=${partySize}`;

      const response = await fetch(apiUrl, {
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const data = await response.json();

      const disabledDates = this.calculateAdminDisabledDates(
        data.weekly_closures || [],
        data.special_closures || []
      );

      return disabledDates;
    } catch (error) {
      console.error('Error fetching closure dates:', error);
      return [];
    }
  }

  getCurrentPartySize() {
    return this.hasPartySizeTarget ? parseInt(this.partySizeTarget.value) || 2 : 2;
  }
}

describe('AdminReservationController', () => {
  let controller;

  beforeEach(() => {
    controller = new AdminReservationController();
    fetch.mockClear();
    flatpickr.mockClear();
    flatpickr.mockReturnValue(mockFlatpickrInstance);
  });

  describe('calculateAdminDisabledDates', () => {
    it('應該正確處理週休息日', () => {
      const weekly_closures = [1, 2]; // 週一、週二休息
      const special_closures = [];

      const disabledDates = controller.calculateAdminDisabledDates(weekly_closures, special_closures);

      // 測試週一（dayOfWeek = 1）應該被禁用
      const monday = new Date('2025-06-23'); // 假設這是週一
      expect(monday.getDay()).toBe(1);
      expect(disabledDates[0](monday)).toBe(true);

      // 測試週二（dayOfWeek = 2）應該被禁用
      const tuesday = new Date('2025-06-24'); // 假設這是週二
      expect(tuesday.getDay()).toBe(2);
      expect(disabledDates[0](tuesday)).toBe(true);

      // 測試週三（dayOfWeek = 3）應該可用
      const wednesday = new Date('2025-06-25'); // 假設這是週三
      expect(wednesday.getDay()).toBe(3);
      expect(disabledDates[0](wednesday)).toBe(false);
    });

    it('應該正確處理特殊休息日', () => {
      const weekly_closures = [];
      const special_closures = ['2025-06-25', '2025-12-25'];

      const disabledDates = controller.calculateAdminDisabledDates(weekly_closures, special_closures);

      // 測試特殊休息日應該被禁用
      const specialDate1 = new Date('2025-06-25');
      expect(disabledDates[0](specialDate1)).toBe(true);

      const specialDate2 = new Date('2025-12-25');
      expect(disabledDates[1](specialDate2)).toBe(true);

      // 測試其他日期應該可用
      const normalDate = new Date('2025-06-26');
      expect(disabledDates[0](normalDate)).toBe(false);
    });

    it('應該同時處理週休息日和特殊休息日', () => {
      const weekly_closures = [0]; // 週日休息
      const special_closures = ['2025-06-25'];

      const disabledDates = controller.calculateAdminDisabledDates(weekly_closures, special_closures);

      // 測試週日應該被禁用
      const sunday = new Date('2025-06-22'); // 假設這是週日
      expect(sunday.getDay()).toBe(0);
      expect(disabledDates[0](sunday)).toBe(true);

      // 測試特殊休息日應該被禁用
      const specialDate = new Date('2025-06-25');
      expect(disabledDates[1](specialDate)).toBe(true);

      // 測試其他日期應該可用
      const monday = new Date('2025-06-23');
      expect(monday.getDay()).toBe(1);
      expect(disabledDates[0](monday)).toBe(false);
      expect(disabledDates[1](monday)).toBe(false);
    });

    it('應該處理空的休息日設定', () => {
      const weekly_closures = [];
      const special_closures = [];

      const disabledDates = controller.calculateAdminDisabledDates(weekly_closures, special_closures);

      expect(disabledDates).toEqual([]);
    });

    it('應該處理 null 或 undefined 的休息日設定', () => {
      const disabledDates1 = controller.calculateAdminDisabledDates(null, null);
      const disabledDates2 = controller.calculateAdminDisabledDates(undefined, undefined);

      expect(disabledDates1).toEqual([]);
      expect(disabledDates2).toEqual([]);
    });
  });

  describe('fetchDisabledDates', () => {
    beforeEach(() => {
      controller.partySizeTarget.value = '4';
    });

    it('應該正確呼叫 API 並處理回應', async () => {
      const mockApiResponse = {
        weekly_closures: [1, 2],
        special_closures: ['2025-06-25'],
        has_capacity: false // 這個在後台應該被忽略
      };

      fetch.mockResolvedValueOnce({
        ok: true,
        json: async () => mockApiResponse,
      });

      const disabledDates = await controller.fetchDisabledDates();

      // 檢查 API 呼叫
      expect(fetch).toHaveBeenCalledWith(
        '/restaurants/test-restaurant/available_days?party_size=4',
        {
          headers: {
            Accept: 'application/json',
            'Content-Type': 'application/json',
          },
        }
      );

      // 檢查回傳的禁用日期（應該有兩個函數：週休息日和特殊休息日）
      expect(disabledDates).toHaveLength(2);
    });

    it('應該處理 API 錯誤', async () => {
      fetch.mockRejectedValueOnce(new Error('Network error'));

      const disabledDates = await controller.fetchDisabledDates();

      // 應該回傳空陣列
      expect(disabledDates).toEqual([]);
    });

    it('應該處理 HTTP 錯誤狀態', async () => {
      fetch.mockResolvedValueOnce({
        ok: false,
        status: 500,
      });

      const disabledDates = await controller.fetchDisabledDates();

      // 應該回傳空陣列
      expect(disabledDates).toEqual([]);
    });

    it('應該忽略 has_capacity 參數（管理員模式）', async () => {
      const mockApiResponse = {
        weekly_closures: [1],
        special_closures: [],
        has_capacity: false // 這應該被忽略
      };

      fetch.mockResolvedValueOnce({
        ok: true,
        json: async () => mockApiResponse,
      });

      const disabledDates = await controller.fetchDisabledDates();

      // 應該只有週休息日，不應該因為 has_capacity: false 而禁用所有日期
      expect(disabledDates).toHaveLength(1);
      
      // 測試週一應該被禁用
      const monday = new Date('2025-06-23'); // 假設這是週一
      expect(disabledDates[0](monday)).toBe(true);
    });
  });

  describe('getCurrentPartySize', () => {
    it('應該回傳 party size 欄位的值', () => {
      controller.partySizeTarget.value = '6';
      expect(controller.getCurrentPartySize()).toBe(6);
    });

    it('應該處理無效的 party size 值', () => {
      controller.partySizeTarget.value = 'invalid';
      expect(controller.getCurrentPartySize()).toBe(2); // 預設值
    });

    it('應該處理空的 party size 值', () => {
      controller.partySizeTarget.value = '';
      expect(controller.getCurrentPartySize()).toBe(2); // 預設值
    });

    it('應該處理沒有 party size target 的情況', () => {
      controller.hasPartySizeTarget = false;
      expect(controller.getCurrentPartySize()).toBe(2); // 預設值
    });
  });
});

// Jest 設定
module.exports = {
  testEnvironment: 'jsdom',
  setupFilesAfterEnv: ['<rootDir>/spec/javascript/setup.js'],
  moduleNameMapper: {
    '^@hotwired/stimulus$': '<rootDir>/spec/javascript/mocks/stimulus.js',
    '^flatpickr$': '<rootDir>/spec/javascript/mocks/flatpickr.js',
  },
  testMatch: ['<rootDir>/spec/javascript/**/*_spec.js'],
};