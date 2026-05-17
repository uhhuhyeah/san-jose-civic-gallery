require "test_helper"

module Documents
  class PersistExtractedTextTest < ActiveSupport::TestCase
    setup do
      matter = Civic::Matter.create!(
        legistar_matter_id: 15886,
        matter_file: "26-575"
      )
      @attachment = Civic::MatterAttachment.create!(
        civic_matter_id: matter.id,
        legistar_matter_attachment_id: 39135,
        name: "Agreement"
      )
      @attachment.update!(source_file_checksum_sha256: "abc123")
    end

    test "persists extracted text metadata and content as append-only artifacts" do
      result = ExtractPdfText::Result.new(
        text: "Hello world",
        command_version: "pdftotext 24.02.0",
        extractor_name: "pdftotext"
      )

      record = PersistExtractedText.call(
        matter_attachment: @attachment,
        extraction_result: result
      )

      assert_equal @attachment.id, record.civic_matter_attachment_id
      assert_equal "pdftotext", record.extractor_name
      assert_equal "ok", record.status
      assert_equal 11, record.character_count
      assert_equal "abc123", record.source_file_checksum_sha256

      second_record = PersistExtractedText.call(
        matter_attachment: @attachment,
        extraction_result: result
      )

      assert_equal 2, @attachment.extracted_texts.count
      assert_not_equal record.id, second_record.id
    end
  end
end
