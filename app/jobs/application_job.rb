class ApplicationJob < ActiveJob::Base
  # Transient network blips during a sync should retry with exponential backoff
  # rather than fail permanently and sit silently in Solid Queue.
  retry_on(
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNRESET,
    Errno::ECONNREFUSED,
    SocketError,
    Legistar::ServerError,
    wait: :exponential,
    attempts: 4,
  )

  # Most jobs are safe to discard if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError
end
