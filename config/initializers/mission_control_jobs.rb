# Mission Control - Jobs UI is mounted at /jobs in config/routes.rb.
# The gem requires HTTP basic auth by default (1.0.0+). In production we
# configure it via env vars; in development/test we turn auth off so
# localhost:3000/jobs is reachable without extra setup.
if ENV["MISSION_CONTROL_USERNAME"].present? && ENV["MISSION_CONTROL_PASSWORD"].present?
  MissionControl::Jobs.http_basic_auth_user = ENV["MISSION_CONTROL_USERNAME"]
  MissionControl::Jobs.http_basic_auth_password = ENV["MISSION_CONTROL_PASSWORD"]
elsif Rails.env.local?
  MissionControl::Jobs.http_basic_auth_enabled = false
end
