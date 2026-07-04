require "test_helper"

class CheckFailedJobsJobTest < ActiveSupport::TestCase
  setup do
    @capture_calls = []
    stub_sentry_capture_message(@capture_calls)
  end

  teardown { Sentry.singleton_class.send(:remove_method, :capture_message) rescue nil }

  test "is a no-op when SolidQueue has no failed_executions table (e.g. test env)" do
    # test env runs the async adapter and has no queue DB; the job must bail
    # out cleanly instead of raising over a missing table.
    assert_nothing_raised { CheckFailedJobsJob.perform_now }
    assert_empty @capture_calls
  end

  test "fires a Sentry alert when failed executions meet the threshold" do
    fake_failures = [
      stub_failed_execution("Ingestion::SyncMatterJob", "default", "Net::OpenTimeout", "timed out"),
      stub_failed_execution("Ingestion::SyncMatterJob", "default", "Net::OpenTimeout", "timed out"),
      stub_failed_execution("Documents::ImportMatterAttachmentFileJob", "default", "Documents::SafeHttpClient::HttpError", "HTTP 403"),
      stub_failed_execution("Generated::BackfillAttachmentSummariesJob", "generated_summary", "Net::ReadTimeout", "read timeout"),
      stub_failed_execution("Ingestion::SyncRecentEventsJob", "default", "Errno::ECONNRESET", "reset")
    ]
    with_stubbed_failed_executions(fake_failures) do
      assert_nothing_raised { CheckFailedJobsJob.perform_now(threshold: 5) }
    end

    assert_equal 1, @capture_calls.size
    message, kwargs = @capture_calls.first
    assert_match(/above threshold/, message)
    assert_equal :error, kwargs[:level]
    assert_equal 5, kwargs[:tags][:failed_count]
    assert_equal 5, kwargs[:tags][:threshold]
    # Breakdown is grouped for actionability.
    assert_equal({ "Ingestion::SyncMatterJob" => 2,
                   "Documents::ImportMatterAttachmentFileJob" => 1,
                   "Generated::BackfillAttachmentSummariesJob" => 1,
                   "Ingestion::SyncRecentEventsJob" => 1 },
                 kwargs[:extra][:by_job_class])
    assert_equal({ "Net::OpenTimeout" => 2,
                   "Documents::SafeHttpClient::HttpError" => 1,
                   "Net::ReadTimeout" => 1,
                   "Errno::ECONNRESET" => 1 },
                 kwargs[:extra][:by_exception_class])
  end

  test "stays quiet below the threshold" do
    with_stubbed_failed_executions([
      stub_failed_execution("Ingestion::SyncMatterJob", "default", "Net::OpenTimeout", "timed out")
    ]) do
      assert_nothing_raised { CheckFailedJobsJob.perform_now(threshold: 5) }
    end
    assert_empty @capture_calls
  end

  test "default threshold reads FAILED_JOBS_ALERT_THRESHOLD env var" do
    assert_equal 5, CheckFailedJobsJob.default_alert_threshold

    ENV["FAILED_JOBS_ALERT_THRESHOLD"] = "10"
    assert_equal 10, CheckFailedJobsJob.default_alert_threshold
  ensure
    ENV.delete("FAILED_JOBS_ALERT_THRESHOLD")
  end

  private

  def stub_sentry_capture_message(calls)
    Sentry.define_singleton_method(:capture_message) do |message, **kwargs|
      calls << [ message, kwargs ]
      nil
    end
  end

  # Bypasses both the table-exists guard and the AR query so we can exercise
  # the alert logic without a queue database.
  def with_stubbed_failed_executions(failures)
    SolidQueue::FailedExecution.define_singleton_method(:table_exists?) { true }
    CheckFailedJobsJob.define_singleton_method(:failed_executions) { failures }
    yield
  ensure
    SolidQueue::FailedExecution.singleton_class.send(:remove_method, :table_exists?) rescue nil
    CheckFailedJobsJob.singleton_class.send(:remove_method, :failed_executions) rescue nil
  end

  def stub_failed_execution(job_class, queue, exception_class, message)
    job = Struct.new(:class_name, :queue_name).new(job_class, queue)
    Struct.new(:job, :exception_class, :message).new(job, exception_class, message)
  end
end
