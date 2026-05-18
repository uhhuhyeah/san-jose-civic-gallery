Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "public/events#index"

  namespace :public do
    resources :events, only: [ :index, :show ]
    resources :matters, only: [ :index, :show ]
  end

  # Public transparency page. Lives at root path (not under /public)
  # for discoverability; controller stays in Public:: for organizational
  # consistency with the other front-end controllers.
  get "data", to: "public/data#show", as: :data
end
