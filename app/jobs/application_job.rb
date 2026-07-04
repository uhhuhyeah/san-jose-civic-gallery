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
  # for hours. After exhaustion the block re-raises so Solid Queue records a
  # FailedExecution (visible in Mission Control at /jobs) and sentry-rails
  # captures it automatically — Mission Control only helps if someone looks,
  # so the Sentry alert from CheckFailedJobsJob is the active signal.
  retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 5) do |job, error|
    Rails.logger.warn(
      "ApplicationJob: #{job.class.name} exhausted 5 retries: " \
        "#{error.class}: #{error.message}"
    )
    raise error
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
