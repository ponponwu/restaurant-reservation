require 'rails_helper'

RSpec.describe 'Admin::BusinessPeriods' do
  describe 'GET /index' do
    it 'returns http success' do
      get '/admin/business_periods/index'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /show' do
    it 'returns http success' do
      get '/admin/business_periods/show'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /new' do
    it 'returns http success' do
      get '/admin/business_periods/new'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /create' do
    it 'returns http success' do
      get '/admin/business_periods/create'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /edit' do
    it 'returns http success' do
      get '/admin/business_periods/edit'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /update' do
    it 'returns http success' do
      get '/admin/business_periods/update'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /destroy' do
    it 'returns http success' do
      get '/admin/business_periods/destroy'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /toggle_active' do
    it 'returns http success' do
      get '/admin/business_periods/toggle_active'
      expect(response).to have_http_status(:success)
    end
  end
end
