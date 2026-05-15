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
    end

    test "persists extracted text metadata and content" do
      result = ExtractPdfText::Result.new(
        text: "Hello world",
        command_version: "pdftotext 24.02.0"
      )

      record = PersistExtractedText.call(
        matter_attachment: @attachment,
        extraction_result: result
      )

      assert_equal @attachment.id, record.civic_matter_attachment_id
      assert_equal "pdftotext", record.extractor_name
      assert_equal "ok", record.status
      assert_equal 11, record.character_count
    end
  end
end
