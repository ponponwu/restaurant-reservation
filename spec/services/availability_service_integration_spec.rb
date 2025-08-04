require 'rails_helper'

RSpec.describe AvailabilityService, type: :service do
  let(:restaurant) { create(:restaurant) }
  let(:reservation_period) { create(:reservation_period, restaurant: restaurant) }
  let(:service) { described_class.new(restaurant) }
  let(:tomorrow) { Date.current + 1.day }

  before do
    # 建立基本的桌位設定
    table_group = create(:table_group, restaurant: restaurant)
    create(:table, restaurant: restaurant, table_group: table_group, capacity: 4, max_capacity: 4)

    # 確保 reservation_period 在測試日期有營業 (設定為每天營業)
    reservation_period.update!(days_of_week: %w[monday tuesday wednesday thursday friday saturday sunday])
  end

  describe 'Integration with both closure systems' do
    context 'when both old and new closure systems exist' do
      let!(:old_closure) do
        create(:closure_date,
               restaurant: restaurant,
               date: tomorrow + 1.day,
               recurring: false)
      end

      let!(:new_closure) do
        create(:special_reservation_date, :closed,
               restaurant: restaurant,
               start_date: tomorrow + 2.days,
               end_date: tomorrow + 2.days)
      end

      let!(:custom_hours_date) do
        create(:special_reservation_date, :custom_hours,
               restaurant: restaurant,
               start_date: tomorrow + 3.days,
               end_date: tomorrow + 3.days)
      end

      it 'respects old closure system dates' do
        closed_date = tomorrow + 1.day
        expect(service.has_any_availability_on_date?(closed_date, 2)).to be false
      end

      it 'respects new closure system dates' do
        closed_date = tomorrow + 2.days
        expect(service.has_any_availability_on_date?(closed_date, 2)).to be false
      end

      it 'handles custom hours dates correctly' do
        custom_date = tomorrow + 3.days
        # 應該有可用性，因為是自訂時段而不是完全關閉
        expect(service.has_any_availability_on_date?(custom_date, 2)).to be true
      end

      it 'handles normal dates correctly' do
        normal_date = tomorrow
        # 正常營業日應該有可用性
        expect(service.has_any_availability_on_date?(normal_date, 2)).to be true
      end
    end

    context 'when checking date ranges with mixed closures' do
      let!(:old_closure) do
        create(:closure_date,
               restaurant: restaurant,
               date: tomorrow,
               recurring: false)
      end

      let!(:new_closure) do
        create(:special_reservation_date, :closed,
               restaurant: restaurant,
               start_date: tomorrow + 1.day,
               end_date: tomorrow + 1.day)
      end

      it 'correctly identifies unavailable dates from both systems' do
        start_date = tomorrow
        end_date = tomorrow + 5.days

        unavailable_dates = []
        (start_date..end_date).each do |date|
          unavailable_dates << date unless service.has_any_availability_on_date?(date, 2)
        end

        # 應該包含兩個關閉日期
        expect(unavailable_dates).to include(tomorrow) # 舊系統
        expect(unavailable_dates).to include(tomorrow + 1.day) # 新系統
        expect(unavailable_dates.length).to eq(2)
      end
    end

    context 'priority handling between systems' do
      let!(:old_closure) do
        create(:closure_date,
               restaurant: restaurant,
               date: tomorrow,
               recurring: false)
      end

      let!(:new_custom_hours) do
        # 建立時間較晚的特殊訂位日將優先生效
        create(:special_reservation_date, :custom_hours,
               restaurant: restaurant,
               start_date: tomorrow,
               end_date: tomorrow)
      end

      it 'prioritizes new system over old system for the same date' do
        # 新系統的自訂時段應該覆蓋舊系統的關閉日期
        expect(service.has_any_availability_on_date?(tomorrow, 2)).to be true
      end
    end
  end
end
