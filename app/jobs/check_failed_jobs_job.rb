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
#
# Runs on the solid_queue_recurring queue (not :default) so a clogged default
# queue cannot delay the very alert that's supposed to notice the clog.
class CheckFailedJobsJob < ApplicationJob
  queue_as :solid_queue_recurring

  # Alert once the failed-execution count (within the lookback window) crosses
  # this many rows. Tuned to stay quiet during a single transient retry storm
  # (a few failures) and fire only when something is persistently breaking.
  # Override per-environment with FAILED_JOBS_ALERT_THRESHOLD.
  DEFAULT_ALERT_THRESHOLD = 5

  # Only count failures newer than this so a stale, uncleared backlog can't
  # alert every hour forever — once a failure ages out of the window it stops
  # counting even if nobody cleared it. Override with FAILED_JOBS_LOOKBACK_HOURS.
  DEFAULT_LOOKBACK_HOURS = 24

  # Cap on rows loaded for the grouped alert payload, to bound memory when the
  # backlog is large. Grouping is over this sample; the count above is exact.
  SAMPLE_LIMIT = 500

  def perform(threshold: self.class.default_alert_threshold, lookback_hours: self.class.default_lookback_hours)
    return unless defined?(SolidQueue)
    return unless SolidQueue::FailedExecution.table_exists?

    scope = self.class.recent_failed_executions_scope(lookback_hours:)
    count = scope.count
    Rails.logger.info(
      "CheckFailedJobsJob: #{count} failed Solid Queue executions " \
        "in the last #{lookback_hours}h (threshold=#{threshold})"
    )
    return if count < threshold

    # Only load rows for the alert payload, and only a bounded sample.
    failures = scope.includes(:job).limit(SAMPLE_LIMIT).to_a
    Sentry.capture_message(
      "Solid Queue failed jobs above threshold (#{count} >= #{threshold}, last #{lookback_hours}h)",
      level: :error,
      tags: {
        check: "solid_queue_failed_jobs",
        failed_count: count,
        threshold: threshold,
        lookback_hours: lookback_hours
      },
      extra: alert_extra(failures, exact_count: count, sampled: failures.size < count)
    )
  end

  class << self
    def default_alert_threshold
      Integer(ENV["FAILED_JOBS_ALERT_THRESHOLD"], exception: false) || DEFAULT_ALERT_THRESHOLD
    end

    def default_lookback_hours
      Integer(ENV["FAILED_JOBS_LOOKBACK_HOURS"], exception: false) || DEFAULT_LOOKBACK_HOURS
    end

    # Scope over failed executions within the lookback window. Extracted as a
    # class method so tests can stub the count/sample without standing up the
    # queue database. Pass `lookback_hours: nil` to count the full backlog.
    def recent_failed_executions_scope(lookback_hours:)
      scope = SolidQueue::FailedExecution
      return scope if lookback_hours.blank?

      cutoff = Time.current - lookback_hours.hours
      scope.where(created_at: cutoff..)
    end
  end

  private

  # Group the sample so the alert is immediately actionable: which job classes
  # and which exception classes are piling up. `sampled: true` is set on the
  # extra when the sample was truncated so the operator knows the grouping is
  # approximate, not exhaustive.
  def alert_extra(failures, exact_count:, sampled:)
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

    {
      exact_failed_count: exact_count,
      sampled: sampled,
      by_job_class: by_job,
      by_exception_class: by_exception,
      sample: sample
    }
  end
end
