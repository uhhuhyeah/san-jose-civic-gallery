require "test_helper"

module Operations
  class AlertOnFailedJobsJobTest < ActiveJob::TestCase
    test "no crash and no Sentry call when solid queue table is absent" do
      sentry = FakeSentry.new
      executions = FakeFailedExecutions.new(table_exists: false)

      AlertOnFailedJobsJob.perform_now(sentry: sentry, failed_executions: executions)

      assert_empty sentry.calls
    end

    test "no Sentry call when count is below default threshold" do
      sentry = FakeSentry.new
      executions = FakeFailedExecutions.new(count: 3)

      AlertOnFailedJobsJob.perform_now(sentry: sentry, failed_executions: executions)

      assert_empty sentry.calls
    end

    test "sends Sentry warning when count equals default threshold" do
      sentry = FakeSentry.new
      executions = FakeFailedExecutions.new(count: 10)

      AlertOnFailedJobsJob.perform_now(sentry: sentry, failed_executions: executions)

      assert_equal 1, sentry.calls.size
      message, kwargs = sentry.calls.first
      assert_includes message, "10"
      assert_equal :warning, kwargs[:level]
    end

    test "sends Sentry warning when count exceeds default threshold" do
      sentry = FakeSentry.new
      executions = FakeFailedExecutions.new(count: 15)

      AlertOnFailedJobsJob.perform_now(sentry: sentry, failed_executions: executions)

      assert_equal 1, sentry.calls.size
    end

    test "respects threshold: and since_minutes: arguments" do
      sentry = FakeSentry.new
      executions = FakeFailedExecutions.new(count: 5)

      travel_to(Time.zone.parse("2026-07-06 12:00:00 UTC")) do
        AlertOnFailedJobsJob.perform_now(
          threshold: 5,
          since_minutes: 30,
          sentry: sentry,
          failed_executions: executions
        )

        assert_equal 1, sentry.calls.size
        range = executions.where_args[:created_at]
        assert_kind_of Range, range
        assert_equal 30.minutes.ago, range.begin
      end
    end

    test "no Sentry call when custom threshold is not met" do
      sentry = FakeSentry.new
      executions = FakeFailedExecutions.new(count: 4)

      AlertOnFailedJobsJob.perform_now(
        threshold: 5,
        sentry: sentry,
        failed_executions: executions
      )

      assert_empty sentry.calls
    end

    FakeSentry = Struct.new(:calls) do
      def initialize(*)
        super([])
      end

      def capture_message(message, **kwargs)
        calls << [ message, kwargs ]
      end
    end

    FakeFailedExecutions = Struct.new(:count, :table_exists, :where_args) do
      def initialize(count: 0, table_exists: true)
        super(count, table_exists, nil)
      end

      def table_exists?
        table_exists
      end

      def where(**kwargs)
        self.where_args = kwargs
        self
      end
    end
  end
end
