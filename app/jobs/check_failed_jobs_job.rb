# Recurring operational check that ends the silence around failed Solid
# Queue jobs. Mission Control (/jobs) shows failures, but only when someone
# looks; this job actively fires a Sentry alert when failures accumulate so a
# chronic ingestion or extraction breakage surfaces instead of stalling the
# pipeline quietly.
#
# It does not retry or discard anything — recovery is a human call via
# Mission Control. The alert is deliberately a `capture_message` (not an
# exception) so it groups as its own Sentry issue and is rate-limited by the
# recurring schedule rather than by every individual failure.
class CheckFailedJobsJob < ApplicationJob
  queue_as :default

  # Alert once the failed-execution backlog crosses this many rows. Tuned to
  # stay quiet during a single transient retry storm (a few failures) and
  # fire only when something is persistently breaking. Override per-environment
  # with FAILED_JOBS_ALERT_THRESHOLD.
  DEFAULT_ALERT_THRESHOLD = 5

  def perform(threshold: self.class.default_alert_threshold)
    return unless defined?(SolidQueue)
    return unless SolidQueue::FailedExecution.table_exists?

    failures = self.class.failed_executions
    count = failures.size
    Rails.logger.info("CheckFailedJobsJob: #{count} failed Solid Queue executions (threshold=#{threshold})")
    return if count < threshold

    Sentry.capture_message(
      "Solid Queue failed jobs above threshold (#{count} >= #{threshold})",
      level: :error,
      tags: { check: "solid_queue_failed_jobs", failed_count: count, threshold: threshold },
      extra: alert_extra(failures)
    )
  end

  class << self
    def default_alert_threshold
      Integer(ENV["FAILED_JOBS_ALERT_THRESHOLD"], exception: false) || DEFAULT_ALERT_THRESHOLD
    end

    # Current failed Solid Queue executions with their owning job preloaded.
    # Extracted as a class method so tests can stub it without standing up
    # the queue database.
    def failed_executions
      SolidQueue::FailedExecution.includes(:job).to_a
    end
  end

  private

  # Group failures so the alert is immediately actionable: which job classes
  # and which exception classes are piling up. Caps the per-group sample to
  # keep the Sentry event payload bounded.
  def alert_extra(failures)
    by_job = failures
      .group_by { |f| f.job&.class_name || "unknown" }
      .transform_values(&:size)

    by_exception = failures
      .group_by { |f| f.exception_class || "unknown" }
      .transform_values(&:size)

    sample = failures.first(3).map do |f|
      {
        job_class: f.job&.class_name,
        queue: f.job&.queue_name,
        exception_class: f.exception_class,
        message: f.message
      }
    end

    { by_job_class: by_job, by_exception_class: by_exception, sample: sample }
  end
end
