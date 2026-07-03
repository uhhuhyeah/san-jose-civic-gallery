# frozen_string_literal: true

module SolidQueueHealth
  # Recurring job that counts SolidQueue::FailedExecution records and reports
  # a Sentry warning when failures accumulate beyond a threshold.  This is the
  # "failed-job visibility" half of the retry hardening in ApplicationJob.
  #
  # Mission Control (/jobs) still exists for manual inspection; this job makes
  # sure someone notices even when nobody is looking at the dashboard.
  class HealthCheckJob < ApplicationJob
    queue_as :solid_queue_recurring

    # Threshold: alert when this many jobs have failed within the lookback window.
    ALERT_THRESHOLD = ENV.fetch("QUEUE_HEALTH_ALERT_THRESHOLD", "5").to_i
    # How far back to look for failed executions (default 1 hour).
    LOOKBACK_WINDOW = ENV.fetch("QUEUE_HEALTH_LOOKBACK_MINUTES", "60").to_i.minutes

    def perform
      count = SolidQueue::FailedExecution.where(
        created_at: Time.current - LOOKBACK_WINDOW..Time.current,
      ).count

      if count > ALERT_THRESHOLD
        Sentry.capture_message(
          "Solid Queue: #{count} failed executions in the last #{LOOKBACK_WINDOW} minutes",
          level: :warning,
          tags: {
            queue: "failed_executions",
            lookback_minutes: LOOKBACK_WINDOW.to_i,
            alert_threshold: ALERT_THRESHOLD,
          },
        )
      end

      Rails.logger.info("Queue health check: #{count} failed executions (threshold #{ALERT_THRESHOLD})")
    end
  end
end
