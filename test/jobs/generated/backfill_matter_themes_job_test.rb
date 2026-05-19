require "test_helper"

module Generated
  class BackfillMatterThemesJobTest < ActiveJob::TestCase
    test "uses the generated summary queue" do
      assert_equal "generated_summary", BackfillMatterThemesJob.queue_name
    end

    test "delegates to the backfill service" do
      calls = []
      result = BackfillMatterThemes::Result.new(
        dry_run: false,
        candidates: [],
        generated: 0,
        failed: 0,
        skipped: 0
      )

      original_call = BackfillMatterThemes.method(:call)
      BackfillMatterThemes.define_singleton_method(:call) do |**kwargs|
        calls << kwargs
        result
      end

      begin
        BackfillMatterThemesJob.perform_now(limit: 25, dry_run: false, force: true)
      ensure
        BackfillMatterThemes.define_singleton_method(:call, original_call)
      end

      assert_equal [ { limit: 25, dry_run: false, force: true } ], calls
    end
  end
end
