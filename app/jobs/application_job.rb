class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Retry transient network errors with exponential backoff.
  retry_on Errno::ECONNRESET,
          Net::OpenTimeout,
          Net::ReadTimeout,
          Documents::SafeHttpClient::HttpError do |exception|
    if exception.is_a?(Documents::SafeHttpClient::HttpError)
      status = exception.status.to_s
      status.start_with?("5") || status == ""
    else
      true
    end
  end, wait: ->(attempt) { (2**attempt).seconds }, tries: 5

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError
end
