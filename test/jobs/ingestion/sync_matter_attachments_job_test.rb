require "test_helper"

module Ingestion
  class SyncMatterAttachmentsJobTest < ActiveJob::TestCase
    test "loads the matter and syncs attachments with a source-matched client" do
      matter = Civic::Matter.create!(
        legistar_matter_id: 27_001,
        matter_file: "26-701",
        source_system: "legistar.sanjose"
      )
      fake_client = Object.new
      calls = []

      replace_class_method(Legistar::Client, :new, ->(source_system:) {
        calls << [ :client, source_system ]
        fake_client
      }) do
        replace_class_method(SyncMatterAttachments, :call, ->(matter:, client:) {
          calls << [ :sync, matter.id, client ]
          Data.define(:attachments).new([])
        }) do
          result = SyncMatterAttachmentsJob.perform_now(matter.id)

          assert_equal [], result.attachments
        end
      end

      assert_equal [
        [ :client, "legistar.sanjose" ],
        [ :sync, matter.id, fake_client ]
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
