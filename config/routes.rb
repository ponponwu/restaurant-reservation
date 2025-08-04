Rails.application.routes.draw do
  devise_for :users

  # 根路徑指向首頁
  root 'home#index'

  # 首頁
  get 'home', to: 'home#index'

  # 短網址重定向路由
  get '/s/:token', to: 'short_urls#redirect', as: 'short_url_redirect'

  # 餐廳前台路由（放在前面，避免與 admin 衝突）
  get '/restaurant/:slug', to: 'restaurants#show', as: 'restaurant_public'

  # 訂位相關 API 路由（具體路由必須放在通用路由之前）
  get '/restaurants/:slug/available_days', to: 'restaurants#available_days', as: 'restaurant_available_days'
  get '/restaurants/:slug/available_dates', to: 'restaurants#available_dates', as: 'restaurant_available_dates'
  get '/restaurants/:slug/available_times', to: 'restaurants#available_times', as: 'restaurant_available_times'
  get '/restaurants/:slug/reservations/availability_status', to: 'reservations#availability_status', as: 'restaurant_availability_status'
  get '/restaurants/:slug/reservations/available_slots', to: 'reservations#available_slots', as: 'restaurant_available_slots'

  # 客戶自助取消訂位（通用路由放在後面）
  get '/restaurants/:slug/reservations/:token', to: 'customer_cancellations#show', as: 'restaurant_reservation_cancel'
  post '/restaurants/:slug/reservations/:token', to: 'customer_cancellations#create'

  get '/restaurant/:slug/reservation', to: 'reservations#new', as: 'new_restaurant_reservation'
  post '/restaurant/:slug/reservation', to: 'reservations#create', as: 'restaurant_reservations'

  # 管理後台
  namespace :admin do
    root 'dashboard#index'

    # 密碼修改
    resource :password_change, only: %i[show update]

    # 管理員管理
    resources :users, except: [:show] do
      member do
        patch :toggle_status
      end
    end

    # 餐廳管理
    resources :restaurants do
      # 黑名單管理
      resources :blacklists do
        member do
          patch :toggle_active
        end
      end

      # 營業時段管理
      resources :operating_hours do
        member do
          patch :toggle_active
        end
      end

      # 預約時段管理
      resources :reservation_periods do
        collection do
          get :edit_day
          post :update_day
          post :disable_day
        end
        member do
          patch :toggle_active
        end
        resources :reservation_slots, except: [:show]
      end

      # 桌位群組管理
      resources :table_groups do
        collection do
          patch :reorder
          get :refresh_priorities
          post :check_name_uniqueness
        end
        member do
          patch :toggle_active
          patch :reorder_tables
        end

        # 嵌套在桌位群組下的桌位
        resources :tables, controller: 'tables', except: [:index] do
          member do
            patch :toggle_active
            patch :update_status
          end
        end
      end

      # 獨立的桌位管理（所有桌位總覽）
      resources :tables, only: %i[index show] do
        member do
          patch :toggle_active
          patch :update_status
          patch :move_to_group
        end
      end

      # 訂位管理
      resources :reservations do
        member do
          patch :cancel
          patch :no_show
        end
        collection do
          get :search
        end
      end

      # 併桌管理
      resources :table_combinations, only: %i[create destroy]

      # 等候清單
      resources :waiting_lists do
        member do
          patch :notify
          patch :cancel
        end
      end
    end

    # 餐廳進階設定 (獨立路由)
    namespace :restaurant_settings do
      resources :restaurants, param: :slug, only: [] do
        get '/', to: 'restaurant_settings#index', as: :index
        # get '/operating_hours', to: 'restaurant_settings#operating_hours', as: :operating_hours
        get '/reservation_periods', to: 'restaurant_settings#reservation_periods', as: :reservation_periods
        get '/closure_dates', to: 'restaurant_settings#closure_dates', as: :closure_dates
        post '/closure_dates', to: 'restaurant_settings#create_closure_date'
        post '/weekly_closure', to: 'restaurant_settings#create_weekly_closure', as: :create_weekly_closure
        delete '/closure_dates/:closure_date_id', to: 'restaurant_settings#destroy_closure_date', as: :destroy_closure_date

        # 週別營業時段管理
        get '/weekly_day/:weekday/edit', to: 'restaurant_settings#edit_weekly_day', as: :edit_weekly_day
        patch '/weekly_day/:weekday', to: 'restaurant_settings#update_weekly_day', as: :update_weekly_day
        post '/weekly_day/copy', to: 'restaurant_settings#copy_weekly_day', as: :copy_weekly_day

        # 特殊日期設定 (新系統)
        resources :special_dates, controller: 'special_dates', except: [:show] do
          member do
            patch :toggle_active
          end
        end

        get '/restaurant_settings', to: 'restaurant_settings#restaurant_settings', as: :restaurant_settings
        patch '/restaurant_settings', to: 'restaurant_settings#update_restaurant_settings'
        put '/restaurant_settings', to: 'restaurant_settings#update_restaurant_settings'

        post '/toggle_day_status', to: 'restaurant_settings#toggle_day_status', as: :toggle_day_status

        get '/reservation_policies', to: 'restaurant_settings#reservation_policies', as: :reservation_policies
        patch '/reservation_policies', to: 'restaurant_settings#update_reservation_policy'
        put '/reservation_policies', to: 'restaurant_settings#update_reservation_policy'
      end
    end

    # 系統設定
    resources :settings, only: %i[index update]

    # 報表
    namespace :reports do
      get :dashboard
      get :reservations
      get :tables
      get :revenue
    end
  end

  # 健康檢查
  get '/health', to: 'health#index'

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "posts#index"
end
