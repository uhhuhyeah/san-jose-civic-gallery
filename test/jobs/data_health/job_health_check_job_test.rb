require "test_helper"

module DataHealth
  class JobHealthCheckJobTest < ActiveSupport::TestCase
    test "perform records a snapshot with zeroes when Solid Queue is absent" do
      # In the test environment SolidQueue::FailedExecution may not exist.
      # The job should gracefully record zeroes.
      assert_difference -> { DataHealth::JobStatusSnapshot.count }, 1 do
        JobHealthCheckJob.perform_now
      end

      snapshot = DataHealth::JobStatusSnapshot.last
      assert_equal 0, snapshot.failed_jobs_last_hour
      assert_equal 0, snapshot.failed_jobs_last_24_hours
      assert_equal :green, snapshot.level
    end
  end
end
