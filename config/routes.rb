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
  get "llms-full.txt", to: "public/discovery#llms_full", defaults: { format: :text }, as: :llms_full
  get "docs/api/v1", to: "public/discovery#api_v1", as: :api_v1_documentation

  namespace :api do
    namespace :v1 do
      get "context", to: "records#context"
      get "matters/search", to: "records#search"
      get "matters/detail", to: "records#detail"
      get "attachments/text-search", to: "records#attachment_text_search"
    end
  end

  match "mcp", to: "mcp#show", via: [ :get, :post, :delete ]

  namespace :public do
    get "meetings", to: "meetings#index"
    resources :events, only: [ :show ]
    get "matters/webmcp-search", to: "matters#webmcp_search", as: :webmcp_matter_search
    get "matters/webmcp-detail", to: "matters#webmcp_detail", as: :webmcp_matter_detail
    get "matters/webmcp-attachment-text", to: "matters#webmcp_attachment_text", as: :webmcp_attachment_text
    resources :matters, only: [ :index, :show ]
  end

  get "glossary", to: "public/glossary#show", as: :glossary

  get "about", to: "public/about#show", as: :about

  # Public transparency page. Lives at root path (not under /public)
  # for discoverability; controller stays in Public:: for organizational
  # consistency with the other front-end controllers.
  get "data", to: "public/data#show", as: :data

  # Monthly roundups
  get "roundups", to: "public/roundups#index", as: :roundups
  get "roundups/:period", to: "public/roundups#show", as: :roundup

  # Durable topical landing pages (issue #152). Root-level paths for
  # discoverability; controllers stay in Public:: so they keep the shared
  # public cache headers and session-skipping.
  get "topics", to: "public/topics#index", as: :topics
  get "topics/:slug", to: "public/topics#show", as: :topic
  get "bodies", to: "public/bodies#index", as: :bodies
  get "bodies/:slug", to: "public/bodies#show", as: :body
  get "years/:year", to: "public/years#show", as: :year, constraints: { year: /\d{4}/ }

  # Legacy preview path, now the homepage. Permanent-redirect any old shared
  # links to root.
  get "pulse-v2", to: redirect("/", status: 301)

  # Atlas redesign development sandbox. Local-only — see DevController. Phase 1
  # design-system PR, see docs/redesign-plan.md.
  if Rails.env.local?
    get "dev/atlas-test", to: "dev#atlas_test", as: :dev_atlas_test
  end
end
