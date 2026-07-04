require "net/http"

class ApplicationJob < ActiveJob::Base
  # Transient upstream failures that should be retried with polynomially
  # increasing backoff rather than failing a sync on the first blip. A brief
  # Legistar/Simbli outage, a reset connection, or an upstream 5xx should not
  # permanently lose a job — the recurring scheduler re-enqueues the next
  # cycle anyway, so retries just smooth over short outages.
  #
  # Permanent 4xx errors (Legistar::Client::HttpClientError, SafeHttpClient
  # 403/404, DisallowedHostError, etc.) are intentionally NOT listed here:
  # retrying a forbidden/gone request would keep failing the same way and
  # would mask data-quality problems that an operator should see.
  TRANSIENT_ERRORS = [
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNRESET,
    Errno::ECONNREFUSED,
    Errno::ETIMEDOUT,
    SocketError,
    Legistar::Client::HttpServerError,
    Legistar::Client::HttpError,
    Documents::SafeHttpClient::HttpServerError,
    Simbli::Client::FetchError
  ].freeze

  # Polynomially longer wait (≈ executions^4 with jitter, +2s floor). Five
  # attempts covers a multi-minute upstream hiccup without blocking the queue
  # for hours. After exhaustion the block re-raises — this is what records a
  # SolidQueue::FailedExecution (visible in Mission Control at /jobs) AND
  # what lets sentry-rails capture the exception. Note: with a block, retry_on
  # does NOT auto-raise, so removing the `raise error` below would silently
  # swallow exhausted failures. The active alert signal is CheckFailedJobsJob;
  # the sentry-rails capture is the per-failure fallback.
  retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 5) do |job, error|
    Rails.logger.warn(
      "ApplicationJob: #{job.class.name} exhausted 5 retries: " \
        "#{error.class}: #{error.message}"
    )
    raise error
  end

  # Vendor anti-bot blocks are not transient — retrying within seconds will
  # keep hitting the same block and burn attempts for nothing, so discard
  # instead of retrying. discard_on prevents a SolidQueue::FailedExecution,
  # so a block would be invisible to Mission Control's failures view and to
  # CheckFailedJobsJob's count. Report it directly to Sentry here so an
  # operator still learns the Simbli pipeline is wedged (its daily 5:30am
  # sync is the only chance to pick up SJUSD meetings for the day). Declared
  # after retry_on because rescue handlers are searched bottom-to-top:
  # BlockedError (a FetchError subclass) matches this first and is discarded;
  # a plain FetchError falls through to the retry above.
  discard_on Simbli::Client::BlockedError do |job, error|
    Rails.logger.warn(
      "ApplicationJob: discarded #{job.class.name} blocked by vendor anti-bot: " \
        "#{error.message}"
    )
    if defined?(Sentry) && Sentry.initialized?
      Sentry.capture_message(
        "Simbli vendor anti-bot block discarded #{job.class.name}",
        level: :warning,
        tags: { check: "simbli_vendor_block", job_class: job.class.name },
        extra: { exception_class: error.class.name, message: error.message }
      )
    end
  end

  # Stale serialized records — the GlobalID-referenced model was deleted
  # between enqueue and perform. Nothing to do; discarding is correct and
  # keeps the queue from wedging on a row that can never succeed.
  discard_on ActiveJob::DeserializationError do |job, error|
    Rails.logger.info(
      "ApplicationJob: discarded #{job.class.name} with stale arguments: " \
        "#{error.class}: #{error.message}"
    )
  end
end
