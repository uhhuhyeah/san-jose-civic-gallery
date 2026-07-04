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
    Sentry.singleton_class.send(:remove_method, :capture_message) rescue nil
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

  test "discards a Simbli vendor anti-bot Block but retries a plain FetchError" do
    blocked_calls = []
    stub_capture_message(blocked_calls)

    blocked_job = Class.new(ApplicationJob) do
      def self.name = "TestSimbliBlockedJob"

      def perform(*)
        raise Simbli::Client::BlockedError, "blocked by Akamai"
      end
    end

    assert_nothing_raised { blocked_job.perform_now(1) }
    # Discarded, not retried — a vendor block won't clear in seconds.
    assert_equal 0, blocked_job.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "TestSimbliBlockedJob" }
    # discard_on produces no FailedExecution, so the block must report itself
    # to Sentry or it would be invisible to Mission Control / CheckFailedJobsJob.
    assert_equal 1, blocked_calls.size
    message, kwargs = blocked_calls.first
    assert_match(/anti-bot block discarded TestSimbliBlockedJob/, message)
    assert_equal :warning, kwargs[:level]
    assert_equal "TestSimbliBlockedJob", kwargs[:tags][:job_class]
    assert_equal "Simbli::Client::BlockedError", kwargs[:extra][:exception_class]

    Sentry.singleton_class.send(:remove_method, :capture_message)

    fetch_job = Class.new(ApplicationJob) do
      def self.name = "TestSimbliFetchJob"

      def perform(*)
        raise Simbli::Client::FetchError, "fetch exited 1: timeout"
      end
    end

    assert_nothing_raised { fetch_job.perform_now(1) }
    # A non-block fetch failure is transient and re-enqueues for retry.
    assert_equal 1, fetch_job.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "TestSimbliFetchJob" }
  end

  private

  def stub_capture_message(calls)
    Sentry.define_singleton_method(:capture_message) do |message, **kwargs|
      calls << [ message, kwargs ]
      nil
    end
  end
end
