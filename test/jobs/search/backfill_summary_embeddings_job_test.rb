require "test_helper"

module Search
  class BackfillSummaryEmbeddingsJobTest < ActiveJob::TestCase
    test "enqueues with default limit" do
      assert_enqueued_with(job: BackfillSummaryEmbeddingsJob) do
        BackfillSummaryEmbeddingsJob.perform_later
      end
    end

    test "enqueues with custom limit" do
      BackfillSummaryEmbeddingsJob.perform_later(limit: 25, dry_run: true)
      assert_enqueued_with(job: BackfillSummaryEmbeddingsJob, args: [ { limit: 25, dry_run: true } ])
    end

    test "runs on generated_summary queue" do
      assert_equal "generated_summary", BackfillSummaryEmbeddingsJob.new.queue_name
    end
  end
end
