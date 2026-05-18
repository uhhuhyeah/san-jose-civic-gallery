require "test_helper"

module Generated
  class BackfillAttachmentSummariesTest < ActiveSupport::TestCase
    setup do
      @matter = Civic::Matter.create!(
        legistar_matter_id: 20_001,
        matter_file: "26-100"
      )
      @client = FakeSummaryClient.new
    end

    test "dry run reports attachments with successful extracted text" do
      candidate = attachment(30_001, "Candidate")
      candidate.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "Text to summarize",
        character_count: 17
      )
      attachment(30_002, "No text")

      result = BackfillAttachmentSummaries.call(limit: 10, dry_run: true, client: @client)

      assert_equal [ candidate.id ], result.candidates.map(&:id)
      assert_equal 0, result.generated
      assert_equal 0, @client.calls
    end

    test "generate mode creates summaries for candidates" do
      candidate = attachment(30_003, "Candidate")
      candidate.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "Text to summarize",
        character_count: 17
      )

      result = BackfillAttachmentSummaries.call(limit: 10, dry_run: false, client: @client)

      assert_equal [ candidate.id ], result.candidates.map(&:id)
      assert_equal 1, result.generated
      assert_equal 1, Artifact.succeeded.count
    end

    test "skips already generated attachments unless forced" do
      candidate = attachment(30_004, "Candidate")
      candidate.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "Text to summarize",
        character_count: 17
      )
      SummarizeMatterAttachment.call(matter_attachment: candidate, client: @client)

      result = BackfillAttachmentSummaries.call(limit: 10, dry_run: true, client: @client)
      forced = BackfillAttachmentSummaries.call(limit: 10, dry_run: true, client: @client, force: true)

      assert_empty result.candidates
      assert_equal [ candidate.id ], forced.candidates.map(&:id)
    end

    private

    def attachment(legistar_id, name)
      @matter.all_attachments.create!(
        legistar_matter_attachment_id: legistar_id,
        name:
      )
    end

    class FakeSummaryClient
      attr_reader :calls, :model_name, :max_input_chars

      def initialize
        @calls = 0
        @model_name = "test-model"
        @max_input_chars = 2_000
      end

      def call(system_prompt:, user_prompt:)
        @calls += 1
        SummaryClient::Response.new(
          model_name:,
          content: {
            "summary" => "Summary from fake model",
            "key_points" => [],
            "limitations" => [],
            "document_status" => "unknown"
          },
          usage_metadata: {}
        )
      end
    end
  end
end
