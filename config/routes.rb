Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Solid Queue inspection UI. Protected by HTTP basic auth in production via
  # MISSION_CONTROL_USERNAME / MISSION_CONTROL_PASSWORD (see config/initializers/mission_control_jobs.rb).
  mount MissionControl::Jobs::Engine, at: "/jobs"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "public/events#index"

  namespace :public do
    get "meetings", to: "meetings#index"
    resources :events, only: [ :index, :show ]
    resources :matters, only: [ :index, :show ]
  end

  get "glossary", to: "public/glossary#show", as: :glossary

  # Public transparency page. Lives at root path (not under /public)
  # for discoverability; controller stays in Public:: for organizational
  # consistency with the other front-end controllers.
  get "data", to: "public/data#show", as: :data

  # Pulse theme-trends preview. Unlinked work-in-progress page (noindex, no nav
  # link). The "-v2" is a temporary route string; the controller is named
  # neutrally so promotion to /pulse is a routes change, not a rename. See
  # docs/pulse.md.
  get "pulse-v2", to: "public/pulse#show", as: :pulse_v2
end
