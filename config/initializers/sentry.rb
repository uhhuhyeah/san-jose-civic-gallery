# frozen_string_literal: true

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]

  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
  config.send_default_pii = false

  config.enable_logs = true
  config.enabled_patches = [ :logger ]

  config.traces_sample_rate = 0.1
  config.profiles_sample_rate = 0.1

  config.before_send_transaction = lambda do |event, _hint|
    if event.request&.url&.include?("/up")
      nil
    else
      event
    end
  end
end
