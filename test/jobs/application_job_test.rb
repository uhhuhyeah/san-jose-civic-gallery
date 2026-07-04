require "test_helper"

class ApplicationJobTest < ActiveSupport::TestCase
  # ApplicationJob uses retry_on with exponential backoff for transient
  # errors and discard_on for deserialization errors. We verify the
  # configuration through source inspection and behavior on perform_now.

  class PermanentErrorJob < ApplicationJob
    def perform
      raise Legistar::Client::HTTPError.new("not found", status: 404)
    end
  end

  test "discard_on is configured for DeserializationError" do
    # discard_on returns nil when queried, so verify via source
    source = File.read(Rails.root.join("app/jobs/application_job.rb"))
    assert source.include?("discard_on ActiveJob::DeserializationError"),
      "expected discard_on for DeserializationError"
  end

  test "permanent 4xx errors fail immediately on perform_now" do
    assert_raises(Legistar::Client::HTTPError) do
      PermanentErrorJob.perform_now
    end
  end

  test "retry_on configuration covers transient error classes" do
    source = File.read(Rails.root.join("app/jobs/application_job.rb"))

    # Verify key error classes are in retry_on
    assert source.include?("Legistar::Client::TransientHTTPError"),
      "expected TransientHTTPError in retry_on"
    assert source.include?("Timeout::Error"),
      "expected Timeout::Error in retry_on"
    assert source.include?("Net::OpenTimeout"),
      "expected Net::OpenTimeout in retry_on"
    assert source.include?("Simbli::Client::FetchError"),
      "expected Simbli::Client::FetchError in retry_on"
    assert source.include?("Errno::ECONNRESET"),
      "expected Errno::ECONNRESET in retry_on"

    # Verify 4xx HTTPError is NOT in retry_on (only TransientHTTPError)
    retry_on_section = source[/retry_on\([^)]+\)/m]
    assert_not_includes retry_on_section, "Legistar::Client::HTTPError,",
      "base HTTPError should not be in retry_on (only TransientHTTPError)"

    # Verify exponential backoff
    assert source.include?("(2 ** attempt).seconds"),
      "expected exponential backoff formula"

    # Verify attempts limit
    assert source.include?("attempts: 4"),
      "expected attempts: 4"

    # Verify Sentry capture block
    assert source.include?("Sentry.capture_exception"),
      "expected Sentry capture on exhaustion"

    # Verify report: true
    assert source.include?("report: true"),
      "expected report: true for error reporter"
  end
end
