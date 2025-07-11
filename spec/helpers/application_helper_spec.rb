require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  let(:restaurant) { create(:restaurant) }

  describe "側邊導航 helper 方法" do
    before do
      allow(helper).to receive(:request).and_return(double('request'))
    end

    describe "#is_current_page?" do
      it "當路徑相符時回傳 true" do
        allow(helper.request).to receive(:path).and_return('/admin')
        expect(helper.is_current_page?('/admin')).to be true
      end

      it "當路徑不相符時回傳 false" do
        allow(helper.request).to receive(:path).and_return('/admin/users')
        expect(helper.is_current_page?('/admin')).to be false
      end
    end

    describe "#is_restaurant_page?" do
      it "當在餐廳詳情頁時回傳 true" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/#{restaurant.id}")
        expect(helper.is_restaurant_page?(restaurant)).to be true
      end

      it "當在餐廳編輯頁時回傳 true" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/#{restaurant.id}/edit")
        expect(helper.is_restaurant_page?(restaurant)).to be true
      end

      it "當不在餐廳相關頁面時回傳 false" do
        allow(helper.request).to receive(:path).and_return("/admin/users")
        expect(helper.is_restaurant_page?(restaurant)).to be false
      end

      it "當餐廳為 nil 時回傳 false" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/1")
        expect(helper.is_restaurant_page?(nil)).to be false
      end
    end

    describe "#is_reservations_page?" do
      it "當在訂位管理頁面時回傳 true" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/#{restaurant.id}/reservations")
        expect(helper.is_reservations_page?(restaurant)).to be true
      end

      it "當在新增訂位頁面時回傳 true" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/#{restaurant.id}/reservations/new")
        expect(helper.is_reservations_page?(restaurant)).to be true
      end

      it "當不在訂位相關頁面時回傳 false" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/#{restaurant.id}")
        expect(helper.is_reservations_page?(restaurant)).to be false
      end
    end

    describe "#is_tables_page?" do
      it "當在桌位群組頁面時回傳 true" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/#{restaurant.id}/table_groups")
        expect(helper.is_tables_page?(restaurant)).to be true
      end

      it "當在桌位總覽頁面時回傳 true" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/#{restaurant.id}/tables")
        expect(helper.is_tables_page?(restaurant)).to be true
      end

      it "當不在桌位相關頁面時回傳 false" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/#{restaurant.id}/reservations")
        expect(helper.is_tables_page?(restaurant)).to be false
      end
    end

    describe "#is_business_periods_page?" do
      it "當在營業時段頁面時回傳 true" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/#{restaurant.id}/business_periods")
        expect(helper.is_business_periods_page?(restaurant)).to be true
      end

      it "當不在營業時段頁面時回傳 false" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/#{restaurant.id}")
        expect(helper.is_business_periods_page?(restaurant)).to be false
      end
    end

    describe "#is_restaurant_settings_page?" do
      it "當在餐廳設定頁面時回傳 true" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurant_settings/restaurants/#{restaurant.slug}")
        expect(helper.is_restaurant_settings_page?(restaurant)).to be true
      end

      it "當不在餐廳設定頁面時回傳 false" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/#{restaurant.id}")
        expect(helper.is_restaurant_settings_page?(restaurant)).to be false
      end
    end

    describe "#is_blacklists_page?" do
      it "當在黑名單頁面時回傳 true" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/#{restaurant.id}/blacklists")
        expect(helper.is_blacklists_page?(restaurant)).to be true
      end

      it "當不在黑名單頁面時回傳 false" do
        allow(helper.request).to receive(:path).and_return("/admin/restaurants/#{restaurant.id}")
        expect(helper.is_blacklists_page?(restaurant)).to be false
      end
    end
  end
end 