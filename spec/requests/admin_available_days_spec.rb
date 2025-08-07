require 'rails_helper'

RSpec.describe 'Admin Available Days API' do
  let(:restaurant) { create(:restaurant, slug: 'test-restaurant') }
  let(:admin_user) { create(:user, :admin, restaurant: restaurant) }

  before do
    # 設定餐廳的營業時段 - 使用新的每日設定模式
    @lunch_periods = create_full_week_periods(restaurant, {
      periods: {
        lunch: { start_time: '11:30', end_time: '14:30', name: '午餐' }
      }
    })
    
    @dinner_periods = create_full_week_periods(restaurant, {
      periods: {
        dinner: { start_time: '17:30', end_time: '21:30', name: '晚餐' }
      }
    })
    
    # 為了向後兼容，設定參考變數
    @lunch_period = @lunch_periods.first
    @dinner_period = @dinner_periods.first

    # 設定桌位群組和桌位
    table_group = restaurant.table_groups.create!(
      name: '主要區域',
      description: '主要用餐區域',
      active: true
    )

    restaurant.restaurant_tables.create!(
      table_number: 'A1',
      capacity: 4,
      min_capacity: 1,
      max_capacity: 4,
      table_type: 'regular',
      operational_status: 'normal',
      sort_order: 1,
      can_combine: true,
      table_group: table_group,
      active: true
    )

    # 這個 API 不需要認證，移除 sign_in
    # sign_in admin_user
  end

  describe 'GET /restaurants/:slug/available_days' do
    context '當餐廳有週休息日設定' do
      before do
        # 設定週一和週二休息（days_of_week_mask 不包含這些天）
        # 127 = 1+2+4+8+16+32+64 (全週)
        # 124 = 4+8+16+32+64 (週三到週日，排除週一週二)
        # 停用週一和週二的餐期 (weekday 1, 2)
        restaurant.reservation_periods.where(weekday: [1, 2]).update_all(active: false)
      end

      it '應該回傳正確的週休息日資訊' do
        get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 2 }

        expect(response).to have_http_status(:success)

        json_response = response.parsed_body

        # 應該包含週一(1)和週二(2)在 weekly_closures 中
        expect(json_response['weekly_closures']).to include(1, 2)
        expect(json_response['weekly_closures']).not_to include(3, 4, 5, 6, 0) # 週三到週日應該營業
      end
    end

    context '當餐廳有特殊休息日設定' do
      let(:special_closure_date) { Date.current + 7.days }

      before do
        restaurant.closure_dates.create!(
          date: special_closure_date,
          reason: '特殊公休',
          recurring: false,
          all_day: true
        )
      end

      it '應該回傳正確的特殊休息日資訊' do
        get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 2 }

        expect(response).to have_http_status(:success)

        json_response = response.parsed_body

        # 應該包含特殊休息日
        expect(json_response['special_closures']).to include(special_closure_date.to_s)
      end
    end

    context '當餐廳沒有足夠容量' do
      before do
        # 刪除所有桌位
        restaurant.restaurant_tables.destroy_all
      end

      it '應該回傳 has_capacity: false' do
        get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 2 }

        expect(response).to have_http_status(:success)

        json_response = response.parsed_body

        # 應該指示沒有容量
        expect(json_response['has_capacity']).to be false
      end

      it '前台會禁用所有日期，但後台邏輯會忽略此設定' do
        get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 2 }

        expect(response).to have_http_status(:success)

        json_response = response.parsed_body

        # API 仍然會回傳 has_capacity: false
        expect(json_response['has_capacity']).to be false

        # 但週休息日和特殊休息日資訊仍然正確
        expect(json_response).to have_key('weekly_closures')
        expect(json_response).to have_key('special_closures')

        # 這裡我們驗證前台和後台的行為差異：
        # 前台會因為 has_capacity: false 而禁用所有日期
        # 後台會忽略 has_capacity，只使用 weekly_closures 和 special_closures
      end
    end

    context '複合情況：週休息日 + 特殊休息日 + 無容量' do
      let(:special_closure_date) { Date.current + 10.days }

      before do
        # 設定週一休息
        # 停用週一的餐期 (weekday 1)
        restaurant.reservation_periods.where(weekday: 1).update_all(active: false)

        # 設定特殊休息日
        restaurant.closure_dates.create!(
          date: special_closure_date,
          reason: '特殊公休',
          recurring: false,
          all_day: true
        )

        # 刪除所有桌位
        restaurant.restaurant_tables.destroy_all
      end

      it '應該回傳所有類型的休息日資訊' do
        get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 4 }

        expect(response).to have_http_status(:success)

        json_response = response.parsed_body

        # 驗證所有資訊都正確回傳
        expect(json_response['weekly_closures']).to include(1) # 週一
        expect(json_response['special_closures']).to include(special_closure_date.to_s)
        expect(json_response['has_capacity']).to be false
        expect(json_response['max_days']).to be_present
      end
    end

    context '當人數參數不同' do
      it '應該根據人數檢查容量（雖然後台會忽略）' do
        # 創建只能容納2人的桌位
        restaurant.restaurant_tables.destroy_all
        restaurant.restaurant_tables.create!(
          table_number: 'Small',
          capacity: 2,
          min_capacity: 1,
          max_capacity: 2,
          table_group: restaurant.table_groups.first,
          active: true
        )

        # 請求2人桌位
        get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 2 }
        json_2_people = response.parsed_body
        expect(json_2_people['has_capacity']).to be true

        # 請求8人桌位
        get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 8 }
        json_8_people = response.parsed_body
        expect(json_8_people['has_capacity']).to be false

        # 但休息日資訊應該相同
        expect(json_2_people['weekly_closures']).to eq(json_8_people['weekly_closures'])
        expect(json_2_people['special_closures']).to eq(json_8_people['special_closures'])
      end
    end

    context '錯誤處理' do
      it '應該處理無效的人數參數' do
        get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 0 }

        expect(response).to have_http_status(:success)

        json_response = response.parsed_body

        # 應該使用預設值並正常回傳
        expect(json_response).to have_key('weekly_closures')
        expect(json_response).to have_key('special_closures')
        expect(json_response).to have_key('has_capacity')
      end

      it '應該處理缺少人數參數' do
        get "/restaurants/#{restaurant.slug}/available_days"

        expect(response).to have_http_status(:success)

        json_response = response.parsed_body

        # 應該使用預設值並正常回傳
        expect(json_response).to have_key('weekly_closures')
        expect(json_response).to have_key('special_closures')
        expect(json_response).to have_key('has_capacity')
      end
    end

    context '性能測試' do
      before do
        # 創建大量特殊休息日
        30.times do |i|
          restaurant.closure_dates.create!(
            date: Date.current + i.days,
            reason: "公休 #{i}",
            recurring: false,
            all_day: true
          )
        end
      end

      it '應該在合理時間內回傳結果' do
        start_time = Time.current

        get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 2 }

        end_time = Time.current
        response_time = end_time - start_time

        expect(response).to have_http_status(:success)
        expect(response_time).to be < 1.second # 應該在1秒內完成

        json_response = response.parsed_body
        expect(json_response['special_closures'].length).to eq(30)
      end
    end
  end

  describe '後台vs前台行為差異' do
    before do
      # 設定一個複雜的情況：有週休息日、特殊休息日，且沒有容量
      @lunch_period.update!(days_of_week_mask: 124) # 週一週二休息
      @dinner_period.update!(days_of_week_mask: 124)

      restaurant.closure_dates.create!(
        date: Date.current + 5.days,
        reason: '特殊公休',
        recurring: false,
        all_day: true
      )

      restaurant.restaurant_tables.destroy_all # 沒有容量
    end

    it '前台邏輯會禁用所有日期（容量不足）' do
      get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 4 }

      json_response = response.parsed_body

      # 前台會因為 has_capacity: false 而在 calculateDisabledDates 中禁用所有日期
      expect(json_response['has_capacity']).to be false

      # 但 API 仍然提供完整的休息日資訊
      expect(json_response['weekly_closures']).to include(1, 2)
      expect(json_response['special_closures']).not_to be_empty
    end

    it '後台邏輯只會禁用休息日（忽略容量）' do
      get "/restaurants/#{restaurant.slug}/available_days", params: { party_size: 4 }

      json_response = response.parsed_body

      # 後台會使用 calculateAdminDisabledDates，只處理休息日
      # 驗證後台會獲得的禁用日期邏輯：
      weekly_closures = json_response['weekly_closures']
      special_closures = json_response['special_closures']

      # 週一週二應該被禁用
      expect(weekly_closures).to include(1, 2)

      # 特殊休息日應該被禁用
      expect(special_closures).to include((Date.current + 5.days).to_s)

      # 但 has_capacity: false 會被後台忽略
      expect(json_response['has_capacity']).to be false # API 仍然回傳 false
      # 後台 JavaScript 會忽略這個值，不會因此禁用所有日期
    end
  end
end
