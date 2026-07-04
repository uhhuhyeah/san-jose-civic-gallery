module DataHealth
  # Records a snapshot of Solid Queue failed-job counts for trend
  # analysis and alerting. Designed to run as a recurring command via
  # config/recurring.yml (not as a dispatched job) so it can safely
  # inspect its own executor's tables.
  class JobHealthCheckJob < ApplicationJob
    queue_as :solid_queue_recurring

    def perform
      counts = count_failed_executions

      snapshot = DataHealth::JobStatusSnapshot.create!(
        failed_jobs_last_hour: counts[:last_hour],
        failed_jobs_last_24_hours: counts[:last_24_hours]
      )

      level = snapshot.level
      log_level = level == :green ? :debug : (level == :amber ? :warn : :error)

      Rails.logger.send(log_level,
        "JobHealthCheckJob: level=#{level} " \
        "failed_last_hour=#{counts[:last_hour]} " \
        "failed_last_24h=#{counts[:last_24_hours]}"
      )

      # When failures accumulate beyond the amber threshold, send a
      # low-priority Sentry event so an alert rule can fire without
      # creating noise for transient single-job failures.
      if level == :red
        Sentry.capture_message(
          "Solid Queue failed-job accumulation",
          level: :warning,
          tags: { job_health_level: level.to_s },
          extra: {
            failed_jobs_last_hour: counts[:last_hour],
            failed_jobs_last_24_hours: counts[:last_24_hours]
          }
        )
      end
    end

    private

    def count_failed_executions
      return { last_hour: 0, last_24_hours: 0 } unless defined?(SolidQueue::FailedExecution)
      return { last_hour: 0, last_24_hours: 0 } unless solid_queue_failed_table_exists?

      {
        last_hour: failed_count_since(1.hour.ago),
        last_24_hours: failed_count_since(24.hours.ago)
      }
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::StatementInvalid, ActiveRecord::TableNotEmptyError
      { last_hour: 0, last_24_hours: 0 }
    end

    def failed_count_since(since)
      return 0 unless defined?(SolidQueue::FailedExecution)

      SolidQueue::FailedExecution.where(created_at: since..).count
    end

    def solid_queue_failed_table_exists?
      return false unless defined?(SolidQueue::FailedExecution)

      connection = SolidQueue::FailedExecution.connection
      connection.data_source_exists?(SolidQueue::FailedExecution.table_name)
    rescue ActiveRecord::ConnectionNotEstablished
      false
    end
  end
end
