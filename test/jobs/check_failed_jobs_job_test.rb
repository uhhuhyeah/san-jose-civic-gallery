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

  test "runs on the solid_queue_recurring queue, not :default" do
    assert_equal "solid_queue_recurring", CheckFailedJobsJob.queue_name
  end

  test "fires a Sentry alert when failed executions meet the threshold" do
    fake_failures = [
      stub_failed_execution("Ingestion::SyncMatterJob", "default", "Net::OpenTimeout", "timed out"),
      stub_failed_execution("Ingestion::SyncMatterJob", "default", "Net::OpenTimeout", "timed out"),
      stub_failed_execution("Documents::ImportMatterAttachmentFileJob", "default", "Documents::SafeHttpClient::HttpError", "HTTP 403"),
      stub_failed_execution("Generated::BackfillAttachmentSummariesJob", "generated_summary", "Net::ReadTimeout", "read timeout"),
      stub_failed_execution("Ingestion::SyncRecentEventsJob", "default", "Errno::ECONNRESET", "reset")
    ]
    with_stubbed_failed_executions(count: 5, sample: fake_failures) do
      assert_nothing_raised { CheckFailedJobsJob.perform_now(threshold: 5) }
    end

    assert_equal 1, @capture_calls.size
    message, kwargs = @capture_calls.first
    assert_match(/above threshold/, message)
    assert_match(/last 24h/, message)
    assert_equal :error, kwargs[:level]
    assert_equal 5, kwargs[:tags][:failed_count]
    assert_equal 5, kwargs[:tags][:threshold]
    assert_equal 24, kwargs[:tags][:lookback_hours]
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
    assert_equal 5, kwargs[:extra][:exact_failed_count]
    assert_not kwargs[:extra][:sampled]
  end

  test "stays quiet below the threshold" do
    with_stubbed_failed_executions(count: 1, sample: [
      stub_failed_execution("Ingestion::SyncMatterJob", "default", "Net::OpenTimeout", "timed out")
    ]) do
      assert_nothing_raised { CheckFailedJobsJob.perform_now(threshold: 5) }
    end
    assert_empty @capture_calls
  end

  test "marks the alert as sampled when the backlog exceeds the sample cap" do
    sample = Array.new(3) { stub_failed_execution("Ingestion::SyncMatterJob", "default", "Net::OpenTimeout", "t") }
    # exact count far exceeds the SAMPLE_LIMIT-loaded sample size
    with_stubbed_failed_executions(count: CheckFailedJobsJob::SAMPLE_LIMIT + 100, sample: sample) do
      assert_nothing_raised { CheckFailedJobsJob.perform_now(threshold: 5) }
    end

    assert_equal 1, @capture_calls.size
    _, kwargs = @capture_calls.first
    assert kwargs[:extra][:sampled]
    assert_equal CheckFailedJobsJob::SAMPLE_LIMIT + 100, kwargs[:extra][:exact_failed_count]
  end

  test "default threshold reads FAILED_JOBS_ALERT_THRESHOLD env var" do
    assert_equal 5, CheckFailedJobsJob.default_alert_threshold

    ENV["FAILED_JOBS_ALERT_THRESHOLD"] = "10"
    assert_equal 10, CheckFailedJobsJob.default_alert_threshold
  ensure
    ENV.delete("FAILED_JOBS_ALERT_THRESHOLD")
  end

  test "default lookback reads FAILED_JOBS_LOOKBACK_HOURS env var" do
    assert_equal 24, CheckFailedJobsJob.default_lookback_hours

    ENV["FAILED_JOBS_LOOKBACK_HOURS"] = "48"
    assert_equal 48, CheckFailedJobsJob.default_lookback_hours
  ensure
    ENV.delete("FAILED_JOBS_LOOKBACK_HOURS")
  end

  private

  def stub_sentry_capture_message(calls)
    Sentry.define_singleton_method(:capture_message) do |message, **kwargs|
      calls << [ message, kwargs ]
      nil
    end
  end

  # Bypasses both the table-exists guard and the AR query so we can exercise
  # the alert logic without a queue database. The scope returned by
  # recent_failed_executions_scope is replaced with a stub that reports the
  # given exact count and yields the given bounded sample.
  def with_stubbed_failed_executions(count:, sample:)
    SolidQueue::FailedExecution.define_singleton_method(:table_exists?) { true }

    stub_scope = Object.new
    stub_scope.define_singleton_method(:count) { count }
    stub_scope.define_singleton_method(:includes) { |_assoc| self }
    stub_scope.define_singleton_method(:limit) { |_n| self }
    stub_scope.define_singleton_method(:to_a) { sample }

    CheckFailedJobsJob.define_singleton_method(:recent_failed_executions_scope) do |lookback_hours:|      stub_scope
    end

    yield
  ensure
    SolidQueue::FailedExecution.singleton_class.send(:remove_method, :table_exists?) rescue nil
    CheckFailedJobsJob.singleton_class.send(:remove_method, :recent_failed_executions_scope) rescue nil
  end

  def stub_failed_execution(job_class, queue, exception_class, message)
    job = Struct.new(:class_name, :queue_name).new(job_class, queue)
    Struct.new(:job, :exception_class, :message).new(job, exception_class, message)
  end
end
