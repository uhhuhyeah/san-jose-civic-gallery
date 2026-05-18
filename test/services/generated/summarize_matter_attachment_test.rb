require "test_helper"

module Generated
  class SummarizeMatterAttachmentTest < ActiveSupport::TestCase
    setup do
      @matter = Civic::Matter.create!(
        legistar_matter_id: 20_001,
        matter_file: "26-100"
      )
      @attachment = @matter.all_attachments.create!(
        legistar_matter_attachment_id: 30_001,
        name: "Staff report"
      )
      @client = FakeSummaryClient.new
    end

    test "creates a generated artifact from latest successful extracted text" do
      extracted_text = extracted_text(content: "The agreement funds library outreach.")

      result = SummarizeMatterAttachment.call(matter_attachment: @attachment, client: @client)

      assert_equal false, result.skipped
      assert_equal "succeeded", result.artifact.status
      assert_equal @attachment, result.artifact.target
      assert_equal extracted_text, result.artifact.source_artifact
      assert_equal "attachment_summary", result.artifact.kind
      assert_equal "test-model", result.artifact.model_identifier
      assert_equal "attachment_summary_v1", result.artifact.prompt_version
      assert_equal "The agreement funds library outreach.", @attachment.extracted_texts.first.content
      assert_equal "Summary from fake model", result.artifact.content.fetch("summary")
    end

    test "does not generate again for the same input, prompt, and model" do
      extracted_text(content: "The agreement funds library outreach.")

      first = SummarizeMatterAttachment.call(matter_attachment: @attachment, client: @client)
      second = SummarizeMatterAttachment.call(matter_attachment: @attachment, client: @client)

      assert_equal first.artifact, second.artifact
      assert_equal true, second.skipped
      assert_equal 1, @client.calls
      assert_equal 1, Artifact.count
    end

    test "changed extracted input creates a new generated artifact" do
      extracted_text(content: "Earlier extracted text.", created_at: 1.day.ago)
      first = SummarizeMatterAttachment.call(matter_attachment: @attachment, client: @client)

      extracted_text(content: "New extracted text.")
      second = SummarizeMatterAttachment.call(matter_attachment: @attachment, client: @client)

      assert_not_equal first.artifact.input_sha256, second.artifact.input_sha256
      assert_equal 2, Artifact.count
    end

    test "missing extracted text records a failed artifact without calling the model" do
      result = SummarizeMatterAttachment.call(matter_attachment: @attachment, client: @client)

      assert_equal "failed", result.artifact.status
      assert_equal "missing_source_text", result.reason
      assert_match(/No successful extracted text/, result.artifact.error_message)
      assert_equal 0, @client.calls
    end

    test "client errors are captured on failed artifacts" do
      extracted_text(content: "The agreement funds library outreach.")
      failing_client = FakeSummaryClient.new(error: RuntimeError.new("budget exceeded"))

      result = SummarizeMatterAttachment.call(matter_attachment: @attachment, client: failing_client)

      assert_equal "failed", result.artifact.status
      assert_equal "budget exceeded", result.artifact.error_message
    end

    test "identical content from a new extracted_text reuses the existing artifact" do
      extracted_text(content: "Identical content.", created_at: 2.days.ago)
      first = SummarizeMatterAttachment.call(matter_attachment: @attachment, client: @client)

      # New extraction row, same content — same input_sha256, no new API call.
      extracted_text(content: "Identical content.")
      second = SummarizeMatterAttachment.call(matter_attachment: @attachment, client: @client)

      assert_equal first.artifact, second.artifact
      assert_equal true, second.skipped
      assert_equal 1, @client.calls
      assert_equal 1, Artifact.count
    end

    test "records truncation provenance in input_metadata" do
      long_content = "x" * 3_000  # client.max_input_chars = 2_000
      extracted_text(content: long_content)

      result = SummarizeMatterAttachment.call(matter_attachment: @attachment, client: @client)

      assert_equal true, result.artifact.input_metadata["truncated"]
      assert_equal 3_000, result.artifact.input_metadata["extracted_character_count"]
      # 2_000 truncated + TRUNCATION_MARKER length
      sent_chars = result.artifact.input_metadata["sent_character_count"]
      assert_operator sent_chars, :>, 2_000
      assert_operator sent_chars, :<, 3_000
      assert_kind_of String, result.artifact.input_metadata["sent_content_sha256"]
    end

    test "bookkeeping failure re-raises the original error rather than swallowing it" do
      extracted_text(content: "Content.")
      failing_client = FakeSummaryClient.new(error: RuntimeError.new("budget exceeded"))

      always_failing_artifact = Artifact.new
      always_failing_artifact.define_singleton_method(:save!) do
        raise ActiveRecord::RecordInvalid.new(self)
      end

      replacement = ->(**_kwargs) { always_failing_artifact }
      with_stubbed_class_method(Artifact, :find_or_initialize_by, replacement) do
        error = assert_raises(RuntimeError) do
          SummarizeMatterAttachment.call(matter_attachment: @attachment, client: failing_client)
        end
        assert_equal "budget exceeded", error.message
      end
    end

    private

    # Replace a class method with the given replacement for the duration of
    # the block, then restore the original. Used to inject a stub without
    # pulling in minitest/mock (which is not bundled).
    def with_stubbed_class_method(klass, method_name, replacement)
      klass.define_singleton_method(method_name, &replacement)
      yield
    ensure
      klass.singleton_class.remove_method(method_name)
    end

    def extracted_text(content:, created_at: Time.current)
      @attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        extractor_version: "24.02",
        status: "ok",
        source_file_checksum_sha256: "source-checksum",
        content:,
        character_count: content.length,
        created_at:
      )
    end

    class FakeSummaryClient
      attr_reader :calls, :model_name, :max_input_chars

      def initialize(error: nil)
        @error = error
        @calls = 0
        @model_name = "test-model"
        @max_input_chars = 2_000
      end

      def call(system_prompt:, user_prompt:)
        @calls += 1
        raise @error if @error

        SummaryClient::Response.new(
          model_name:,
          content: {
            "summary" => "Summary from fake model",
            "key_points" => [ "One point" ],
            "limitations" => []
          }
        )
      end
    end
  end
end
