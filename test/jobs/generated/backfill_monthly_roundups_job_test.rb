require "test_helper"

module Generated
  class BackfillMonthlyRoundupsJobTest < ActiveJob::TestCase
    test "uses the generated summary queue" do
      assert_equal "generated_summary", BackfillMonthlyRoundupsJob.queue_name
    end

    test "delegates to the backfill service" do
      calls = []
      result = BackfillMonthlyRoundups::Result.new(
        dry_run: false,
        candidates: [],
        generated: 0,
        failed: 0,
        skipped: 0
      )

      original_call = BackfillMonthlyRoundups.method(:call)
      BackfillMonthlyRoundups.define_singleton_method(:call) do |**kwargs|
        calls << kwargs
        result
      end

      begin
        BackfillMonthlyRoundupsJob.perform_now(limit: 3, dry_run: false, force: true)
      ensure
        BackfillMonthlyRoundups.define_singleton_method(:call, original_call)
      end

      assert_equal [ { limit: 3, dry_run: false, force: true } ], calls
    end
  end
end
