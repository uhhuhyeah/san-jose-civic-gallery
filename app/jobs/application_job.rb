class ApplicationJob < ActiveJob::Base
  # Most jobs are safe to ignore if the underlying records are no longer
  # available (e.g., the matter was deleted before the attachment sync ran).
  discard_on ActiveJob::DeserializationError

  # Transient network / server errors get exponential backoff.
  # 4 attempts = initial + 3 retries at ~2s, ~4s, ~8s.
  # Only 5xx from Legistar are retried (TransientHTTPError); 4xx pass
  # through and are captured by Sentry as permanent failures.
  retry_on(
    Legistar::Client::TransientHTTPError,
    Timeout::Error,
    Errno::ECONNRESET,
    Errno::ECONNREFUSED,
    Errno::ETIMEDOUT,
    EOFError,
    Net::OpenTimeout,
    Simbli::Client::FetchError,
    wait: ->(attempt) { (2 ** attempt).seconds },
    attempts: 4,
    report: true
  ) do |job, error|
    # Called when retries are exhausted. Report to Sentry and re-raise
    # so Solid Queue records the job as failed.
    Sentry.capture_exception(error, extra: { job_class: job.class.name, job_id: job.job_id })
    raise error
  end
end
