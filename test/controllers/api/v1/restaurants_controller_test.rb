require 'test_helper'

module Api
  module V1
    class RestaurantsControllerTest < ActionDispatch::IntegrationTest
      include Devise::Test::IntegrationHelpers
      include ActiveSupport::Testing::TimeHelpers

      setup do
        # 設定時區為台北
        @original_time_zone = Time.zone
        Time.zone = 'Asia/Taipei'

        @restaurant = restaurants(:one)
        @business_period = business_periods(:lunch)
        @table = tables(:table_one)

        # 確保餐廳有關聯的營業時段和桌位
        @restaurant.business_periods << @business_period
        @restaurant.tables << @table

        # 設定預設的預約政策
        @restaurant.create_default_policy unless @restaurant.policy
      end

      teardown do
        # 還原時區設定
        Time.zone = @original_time_zone
      end

      test 'should get available dates' do
        # 設定測試日期（台北時區）
        travel_to Time.zone.local(2025, 6, 10, 12, 0, 0) do
          # 模擬餐廳在 2025-06-15 有營業
          @business_period.update!(days_of_week: { monday: true, tuesday: true, wednesday: true,
                                                   thursday: true, friday: true, saturday: true, sunday: true })

          # 確保沒有公休日
          @restaurant.closure_dates.destroy_all

          get "/restaurant/#{@restaurant.slug}/available_dates",
              params: { party_size: 2 }

          assert_response :success

          json_response = response.parsed_body
          assert_includes json_response['available_dates'], '2025-06-10'  # 今天
          assert_includes json_response['available_dates'], '2025-06-11'  # 明天
          assert_includes json_response['available_dates'], '2025-06-15'  # 下週一
          assert_not_nil json_response['business_periods']
        end
      end

      test 'should handle restaurant closure dates' do
        # 設定測試日期（台北時區）
        travel_to Time.zone.local(2025, 6, 10, 12, 0, 0) do
          # 設定 2025-06-15 為公休日
          @restaurant.closure_dates.create!(closure_date: '2025-06-15', reason: '特別公休')

          get "/restaurant/#{@restaurant.slug}/available_dates",
              params: { party_size: 2 }

          assert_response :success

          json_response = response.parsed_body
          assert_not_includes json_response['available_dates'], '2025-06-15'
        end
      end

      test 'should handle weekly closure days' do
        # 設定測試日期（台北時區）
        travel_to Time.zone.local(2025, 6, 10, 12, 0, 0) do
          # 設定每週一公休
          @business_period.update!(days_of_week: { monday: false, tuesday: true, wednesday: true,
                                                   thursday: true, friday: true, saturday: true, sunday: true })

          get "/restaurant/#{@restaurant.slug}/available_dates",
              params: { party_size: 2 }

          assert_response :success

          json_response = response.parsed_body
          # 2025-06-16 是週一，應該被排除
          assert_not_includes json_response['available_dates'], '2025-06-16'
        end
      end

      test 'should handle timezone correctly' do
        # 測試 UTC 時間轉換為台北時區
        # 當 UTC 時間是 2025-06-10 16:00:00 (即台北時間 2025-06-11 00:00:00)
        travel_to Time.utc(2025, 6, 10, 16, 0, 0) do
          # 設定餐廳每天營業
          @business_period.update!(days_of_week: { monday: true, tuesday: true, wednesday: true,
                                                   thursday: true, friday: true, saturday: true, sunday: true })

          get "/restaurant/#{@restaurant.slug}/available_dates",
              params: { party_size: 2 }

          assert_response :success

          json_response = response.parsed_body
          # 應該包含台北時間的明天（2025-06-11）
          assert_includes json_response['available_dates'], '2025-06-11'
        end
      end

      test 'should return empty when no capacity' do
        # 設定測試日期（台北時區）
        travel_to Time.zone.local(2025, 6, 10, 12, 0, 0) do
          # 設定一個非常小的人數限制，使所有日期都無法預約
          @table.update!(min_capacity: 1, max_capacity: 1)

          get "/restaurant/#{@restaurant.slug}/available_dates",
              params: { party_size: 2 }

          assert_response :success

          json_response = response.parsed_body
          assert_empty json_response['available_dates']
        end
      end
    end
  end
end
