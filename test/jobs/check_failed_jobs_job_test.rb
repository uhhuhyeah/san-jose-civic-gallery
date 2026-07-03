require "test_helper"

class CheckFailedJobsJobTest < ActiveSupport::TestCase
  setup do
    @job = CheckFailedJobsJob.new
  end

  test "captures message when there are failed jobs" do
    SolidQueue::FailedExecution.stub(:count, 3) do
      expected_msg = "SolidQueue has 3 failed job(s). Run `solid_queue:failed` for details."
      captured = nil
      Sentry.stub(:capture_message, ->(msg){ captured = msg }) do
        @job.perform_now
        assert_equal expected_msg, captured
      end
    end
  end

  test "does not capture when there are no failed jobs" do
    SolidQueue::FailedExecution.stub(:count, 0) do
      captured = nil
      Sentry.stub(:capture_message, ->(msg){ captured = msg }) do
        @job.perform_now
        assert_nil captured
      end
    end
  end
end
