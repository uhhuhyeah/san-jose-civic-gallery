require "test_helper"

module Documents
  class ExtractMatterAttachmentTextTest < ActiveSupport::TestCase
    setup do
      matter = Civic::Matter.create!(legistar_matter_id: 17001, matter_file: "26-900")
      @attachment = Civic::MatterAttachment.create!(
        civic_matter_id: matter.id,
        legistar_matter_attachment_id: 41001,
        name: "Memo",
        source_file_checksum_sha256: "deadbeef"
      )
    end

    test "records an error row and re-raises when extraction fails" do
      stub_extractor_to_raise("pdftotext exploded")

      assert_raises(RuntimeError) do
        ExtractMatterAttachmentText.call(matter_attachment: @attachment)
      end

      error_row = Documents::ExtractedText.where(civic_matter_attachment_id: @attachment.id).last
      assert_not_nil error_row
      assert_equal "error", error_row.status
      assert_match(/pdftotext exploded/, error_row.error_message)
      assert_equal "deadbeef", error_row.source_file_checksum_sha256
    end

    test "still re-raises the original error when the bookkeeping insert fails" do
      stub_extractor_to_raise("original failure")
      stub_extracted_text_create_to_raise("DB unavailable")
      logged = capture_rails_logger_error

      error = assert_raises(RuntimeError) do
        ExtractMatterAttachmentText.call(matter_attachment: @attachment)
      end

      assert_equal "original failure", error.message
      assert_match(/DB unavailable/, logged.string)
    end

    private

    def stub_extractor_to_raise(message)
      original = ExtractPdfText.method(:call)
      ExtractPdfText.define_singleton_method(:call) do |matter_attachment:|
        raise message
      end
      @extractor_restorer = -> { ExtractPdfText.define_singleton_method(:call, original) }
    end

    def stub_extracted_text_create_to_raise(message)
      original = ExtractedText.method(:create!)
      ExtractedText.define_singleton_method(:create!) do |*_args, **_kwargs|
        raise message
      end
      @create_restorer = -> { ExtractedText.define_singleton_method(:create!, original) }
    end

    def capture_rails_logger_error
      buffer = StringIO.new
      original_logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(buffer)
      @logger_restorer = -> { Rails.logger = original_logger }
      buffer
    end

    def teardown
      @extractor_restorer&.call
      @create_restorer&.call
      @logger_restorer&.call
    end
  end
end
