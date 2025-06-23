require 'rails_helper'

RSpec.describe 'Business Period Determination' do
  let(:restaurant) { Restaurant.create!(name: 'Test Restaurant', slug: 'test', phone: '02-12345678', address: 'Test Address') }

  before do
    # 清理現有時段並建立測試時段
    restaurant.business_periods.destroy_all

    @lunch_period = restaurant.business_periods.create!(
      name: 'lunch',
      display_name: '午餐',
      start_time: '11:30',
      end_time: '14:30',
      days_of_week_mask: 127,
      active: true
    )

    @dinner_period = restaurant.business_periods.create!(
      name: 'dinner',
      display_name: '晚餐',
      start_time: '17:30',
      end_time: '21:30',
      days_of_week_mask: 127,
      active: true
    )
  end

  describe 'time period matching' do
    context 'exact time matches' do
      it 'matches 19:00 to dinner period' do
        time_19_00 = Time.zone.parse('2025-06-19 19:00:00')
        time_minutes = (time_19_00.hour * 60) + time_19_00.min

        # 使用與控制器相同的邏輯
        period = restaurant.business_periods.active.find do |p|
          start_minutes = (p.start_time.hour * 60) + p.start_time.min
          end_minutes = (p.end_time.hour * 60) + p.end_time.min
          time_minutes >= start_minutes && time_minutes <= end_minutes
        end

        expect(period).to eq(@dinner_period)
        expect(period.name).to eq('dinner')
      end

      it 'matches 13:00 to lunch period' do
        time_13_00 = Time.zone.parse('2025-06-19 13:00:00')
        time_minutes = (time_13_00.hour * 60) + time_13_00.min

        # 使用與控制器相同的邏輯
        period = restaurant.business_periods.active.find do |p|
          start_minutes = (p.start_time.hour * 60) + p.start_time.min
          end_minutes = (p.end_time.hour * 60) + p.end_time.min
          time_minutes >= start_minutes && time_minutes <= end_minutes
        end

        expect(period).to eq(@lunch_period)
        expect(period.name).to eq('lunch')
      end
    end

    context 'boundary times' do
      it 'matches exact start time 17:30 to dinner' do
        time_17_30 = Time.zone.parse('2025-06-19 17:30:00')
        time_minutes = (time_17_30.hour * 60) + time_17_30.min

        period = restaurant.business_periods.active.find do |p|
          start_minutes = (p.start_time.hour * 60) + p.start_time.min
          end_minutes = (p.end_time.hour * 60) + p.end_time.min
          time_minutes >= start_minutes && time_minutes <= end_minutes
        end

        expect(period).to eq(@dinner_period)
      end

      it 'matches exact end time 21:30 to dinner' do
        time_21_30 = Time.zone.parse('2025-06-19 21:30:00')
        time_minutes = (time_21_30.hour * 60) + time_21_30.min

        period = restaurant.business_periods.active.find do |p|
          start_minutes = (p.start_time.hour * 60) + p.start_time.min
          end_minutes = (p.end_time.hour * 60) + p.end_time.min
          time_minutes >= start_minutes && time_minutes <= end_minutes
        end

        expect(period).to eq(@dinner_period)
      end
    end

    context 'timezone handling' do
      it 'correctly handles UTC to Taipei timezone conversion' do
        # UTC 11:00 = 台北 19:00
        utc_time = Time.parse('2025-06-19 11:00:00 UTC')
        taipei_time = utc_time.in_time_zone('Asia/Taipei')

        expect(taipei_time.strftime('%H:%M:%S')).to eq('19:00:00')

        time_minutes = (taipei_time.hour * 60) + taipei_time.min

        period = restaurant.business_periods.active.find do |p|
          start_minutes = (p.start_time.hour * 60) + p.start_time.min
          end_minutes = (p.end_time.hour * 60) + p.end_time.min
          time_minutes >= start_minutes && time_minutes <= end_minutes
        end

        expect(period).to eq(@dinner_period)
        expect(period.name).to eq('dinner')
      end
    end
  end

  describe 'current business periods configuration' do
    it 'has correct lunch period timing' do
      expect(@lunch_period.start_time.strftime('%H:%M')).to eq('11:30')
      expect(@lunch_period.end_time.strftime('%H:%M')).to eq('14:30')
    end

    it 'has correct dinner period timing' do
      expect(@dinner_period.start_time.strftime('%H:%M')).to eq('17:30')
      expect(@dinner_period.end_time.strftime('%H:%M')).to eq('21:30')
    end

    it 'confirms 19:00 is within dinner period range' do
      start_decimal = @dinner_period.start_time.hour + (@dinner_period.start_time.min / 60.0)
      end_decimal = @dinner_period.end_time.hour + (@dinner_period.end_time.min / 60.0)
      time_19_00_decimal = 19.0

      expect(time_19_00_decimal).to be >= start_decimal
      expect(time_19_00_decimal).to be <= end_decimal
      expect(start_decimal).to eq(17.5)  # 17:30
      expect(end_decimal).to eq(21.5)    # 21:30
    end
  end
end
