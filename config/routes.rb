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

  # The Pulse theme-trends page is the homepage. The former events index still
  # lives at /public/events. See docs/pulse.md.
  root "public/pulse#show"

  get "robots.txt", to: "public/discovery#robots", defaults: { format: :text }, as: :robots
  get "sitemap.xml", to: "public/discovery#sitemap", defaults: { format: :xml }, as: :sitemap
  get "llms.txt", to: "public/discovery#llms", defaults: { format: :text }, as: :llms

  namespace :public do
    get "meetings", to: "meetings#index"
    resources :events, only: [ :show ]
    resources :matters, only: [ :index, :show ]
  end

  get "glossary", to: "public/glossary#show", as: :glossary

  # Public transparency page. Lives at root path (not under /public)
  # for discoverability; controller stays in Public:: for organizational
  # consistency with the other front-end controllers.
  get "data", to: "public/data#show", as: :data

  # Legacy preview path, now the homepage. Permanent-redirect any old shared
  # links to root.
  get "pulse-v2", to: redirect("/", status: 301)
end
