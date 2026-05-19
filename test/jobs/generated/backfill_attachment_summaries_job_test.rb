require "test_helper"

module Generated
  class BackfillAttachmentSummariesJobTest < ActiveJob::TestCase
    test "uses the generated summary queue" do
      assert_equal "generated_summary", BackfillAttachmentSummariesJob.queue_name
    end

    test "delegates to the backfill service" do
      calls = []
      result = BackfillAttachmentSummaries::Result.new(
        dry_run: false,
        candidates: [],
        generated: 0,
        failed: 0,
        skipped: 0
      )

      original_call = BackfillAttachmentSummaries.method(:call)
      BackfillAttachmentSummaries.define_singleton_method(:call) do |**kwargs|
        calls << kwargs
        result
      end

      begin
        BackfillAttachmentSummariesJob.perform_now(limit: 25, dry_run: false, force: true)
      ensure
        BackfillAttachmentSummaries.define_singleton_method(:call, original_call)
      end

      assert_equal [ { limit: 25, dry_run: false, force: true } ], calls
    end
  end
end
