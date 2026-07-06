module Operations
  class AlertOnFailedJobsJob < ApplicationJob
    queue_as :default

    def perform(threshold: nil, since_minutes: nil, sentry: Sentry, failed_executions: SolidQueue::FailedExecution)
      threshold ||= ENV.fetch("FAILED_JOB_ALERT_THRESHOLD", 10).to_i
      since_minutes ||= ENV.fetch("FAILED_JOB_ALERT_WINDOW", 60).to_i

      return unless failed_executions.table_exists?

      count = failed_executions
        .where(created_at: since_minutes.minutes.ago..)
        .count

      if count >= threshold
        sentry.capture_message(
          "High failed job count (#{count} in last #{since_minutes} minutes)",
          level: :warning,
          tags: { solid_queue_failures: count.to_s }
        )
      end
    end
  end
end
