require "test_helper"

module SolidQueueHealth
  class HealthCheckJobTest < ActiveSupport::TestCase
    # Solid Queue tables live in a separate database and won't exist in the
    # test DB, so we stub both the FailedExecution query and Sentry capture.
    #
    # ALERT_THRESHOLD defaults to 5. We test against that default rather than
    # trying to re-open the constant.

    test "does not alert when failed executions are below threshold" do
      fake_scope = Object.new
      fake_scope.define_singleton_method(:count) { 0 }

      called = false
      orig_capture = Sentry.method(:capture_message)
      Sentry.define_singleton_method(:capture_message, ->(*, **) { called = true })

      orig_where = SolidQueue::FailedExecution.method(:where)
      SolidQueue::FailedExecution.define_singleton_method(:where, ->(*) { fake_scope })

      SolidQueueHealth::HealthCheckJob.perform_now

      refute called, "Sentry.capture_message should not have been called"
    ensure
      Sentry.define_singleton_method(:capture_message, orig_capture)
      SolidQueue::FailedExecution.define_singleton_method(:where, orig_where)
    end

    test "alerts via Sentry when failed executions exceed threshold" do
      fake_scope = Object.new
      fake_scope.define_singleton_method(:count) { 6 } # default threshold is 5

      captured = nil
      orig_capture = Sentry.method(:capture_message)
      Sentry.define_singleton_method(:capture_message) do |msg, **kwargs|
        captured = { message: msg, **kwargs }
      end

      orig_where = SolidQueue::FailedExecution.method(:where)
      SolidQueue::FailedExecution.define_singleton_method(:where, ->(*) { fake_scope })

      SolidQueueHealth::HealthCheckJob.perform_now

      assert captured, "Sentry.capture_message should have been called"
      assert_match(/failed executions/, captured[:message])
      assert_equal :warning, captured[:level]
    ensure
      Sentry.define_singleton_method(:capture_message, orig_capture)
      SolidQueue::FailedExecution.define_singleton_method(:where, orig_where)
    end
  end
end
