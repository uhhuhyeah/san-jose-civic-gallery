class ApplicationJob < ActiveJob::Base
  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # Transient infrastructure / network errors: retry with exponential backoff
  retry_on Net::OpenTimeout,
           Net::ReadTimeout,
           Errno::ECONNRESET,
           Errno::ECONNREFUSED,
           Errno::EHOSTUNREACH,
           Errno::ENETUNREACH,
           SocketError,
           Timeout::Error,
           wait: :polynomially_longer,
           attempts: 5
end
