require "test_helper"

module Ingestion
  class SyncMatterJobTest < ActiveJob::TestCase
    test "syncs a matter through the Legistar client for the requested source system" do
      calls = []
      matter = Civic::Matter.new(legistar_matter_id: 42, matter_file: "26-042")
      fake_client = Object.new

      replace_class_method(Legistar::Client, :new, ->(source_system:) {
        calls << [ :client, source_system ]
        fake_client
      }) do
        replace_class_method(SyncMatter, :call, ->(matter_id:, client:) {
          calls << [ :sync, matter_id, client ]
          Data.define(:matter).new(matter)
        }) do
          result = SyncMatterJob.perform_now(42, source_system: "legistar.other")

          assert_equal matter, result.matter
        end
      end

      assert_equal [
        [ :client, "legistar.other" ],
        [ :sync, 42, fake_client ]
      ], calls
    end

    private

    def replace_class_method(klass, method_name, replacement)
      original = klass.method(method_name)
      klass.define_singleton_method(method_name, &replacement)
      yield
    ensure
      klass.define_singleton_method(method_name, original)
    end
  end
end
