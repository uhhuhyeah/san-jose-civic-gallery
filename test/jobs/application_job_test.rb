require "test_helper"
require "active_job/test_helper"

# Verifies the retry/discard posture configured on ApplicationJob without
# exercising the full Solid Queue stack. Uses the :test queue adapter so
# retries show up as re-enqueued jobs we can count deterministically.
class ApplicationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @previous_adapter = ApplicationJob.queue_adapter
    ApplicationJob.queue_adapter = :test
  end

  teardown do
    ApplicationJob.queue_adapter = @previous_adapter
  end

  test "TRANSIENT_ERRORS covers network and 5xx classes but not permanent 4xx" do
    assert_includes ApplicationJob::TRANSIENT_ERRORS, Net::OpenTimeout
    assert_includes ApplicationJob::TRANSIENT_ERRORS, Net::ReadTimeout
    assert_includes ApplicationJob::TRANSIENT_ERRORS, Errno::ECONNRESET
    assert_includes ApplicationJob::TRANSIENT_ERRORS, Legistar::Client::HttpServerError
    assert_includes ApplicationJob::TRANSIENT_ERRORS, Documents::SafeHttpClient::HttpServerError
    assert_includes ApplicationJob::TRANSIENT_ERRORS, Simbli::Client::FetchError

    # 4xx is intentionally NOT retried — retrying a forbidden/gone request
    # would keep failing and mask data-quality problems.
    assert_not_includes ApplicationJob::TRANSIENT_ERRORS, Legistar::Client::HttpClientError
  end

  test "retries a transient network error by re-enqueuing" do
    job_class = Class.new(ApplicationJob) do
      def self.name = "TestTransientJob"

      def perform(*)
        raise Net::OpenTimeout, "upstream blip"
      end
    end

    assert_nothing_raised { job_class.perform_now(1) }
    # First attempt failed transiently -> retry_on re-enqueues rather than
    # surfacing the error on the first attempt.
    assert_equal 1, job_class.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "TestTransientJob" }
  end

  test "does not retry a permanent (non-transient) error" do
    job_class = Class.new(ApplicationJob) do
      def self.name = "TestPermanentJob"

      def perform(*)
        raise ArgumentError, "bad input"
      end
    end

    assert_raises(ArgumentError) { job_class.perform_now(1) }
    assert_equal 0, job_class.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "TestPermanentJob" }
  end

  test "discards ActiveJob::DeserializationError instead of failing" do
    job_class = Class.new(ApplicationJob) do
      def self.name = "TestStaleRecordJob"

      def perform(record)
        begin
          raise StandardError, "could not deserialize #{record}"
        rescue StandardError
          # DeserializationError reads $! (the current exception) in its
          # initializer, so it must be raised from within a rescue.
          raise ActiveJob::DeserializationError
        end
      end
    end

    assert_nothing_raised { job_class.perform_now("gid://app/Civic::Matter/1") }
    assert_equal 0, job_class.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "TestStaleRecordJob" }
  end
end
