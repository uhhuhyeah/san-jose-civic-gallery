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

    test "persists embedded PDF text without running OCR" do
      embedded_extractor = Class.new do
        def self.call(matter_attachment:)
          ExtractPdfText::Result.new(
            text: "Embedded staff report text",
            command_version: "pdftotext 24.02.0",
            extractor_name: "pdftotext"
          )
        end
      end
      ocr_extractor = Class.new do
        def self.call(matter_attachment:)
          raise "OCR should not run"
        end
      end

      record = ExtractMatterAttachmentText.call(
        matter_attachment: @attachment,
        embedded_extractor:,
        ocr_extractor:
      )

      assert_equal "ok", record.status
      assert_equal "pdftotext", record.extractor_name
      assert_equal "Embedded staff report text", record.content
      assert_equal 1, @attachment.extracted_texts.count
    end

    test "falls back to OCR when embedded PDF text is empty" do
      embedded_extractor = Class.new do
        def self.call(matter_attachment:)
          ExtractPdfText::Result.new(
            text: "",
            command_version: "pdftotext 24.02.0",
            extractor_name: "pdftotext"
          )
        end
      end
      ocr_extractor = Class.new do
        def self.call(matter_attachment:)
          OcrPdfText::Result.new(
            text: "OCR recovered scanned staff report text",
            command_version: "ocrmypdf 16.10.0",
            extractor_name: "ocrmypdf"
          )
        end
      end

      record = ExtractMatterAttachmentText.call(
        matter_attachment: @attachment,
        embedded_extractor:,
        ocr_extractor:
      )

      assert_equal "ok", record.status
      assert_equal "ocrmypdf", record.extractor_name
      assert_equal "ocrmypdf 16.10.0", record.extractor_version
      assert_equal "OCR recovered scanned staff report text", record.content

      records = @attachment.extracted_texts.reorder(:created_at, :id).to_a
      assert_equal 2, records.size
      assert_equal "pdftotext", records.first.extractor_name
      assert_equal "empty", records.first.status
      assert_equal "pdftotext 24.02.0", records.first.extractor_version
      assert_equal "ocrmypdf", records.second.extractor_name
      assert_equal "ok", records.second.status
    end

    test "records an OCR error row when fallback fails" do
      embedded_extractor = Class.new do
        def self.call(matter_attachment:)
          ExtractPdfText::Result.new(
            text: "",
            command_version: "pdftotext 24.02.0",
            extractor_name: "pdftotext"
          )
        end
      end
      ocr_extractor = Class.new do
        def self.call(matter_attachment:)
          raise "ocrmypdf exploded"
        end
      end

      assert_raises(RuntimeError) do
        ExtractMatterAttachmentText.call(
          matter_attachment: @attachment,
          embedded_extractor:,
          ocr_extractor:
        )
      end

      records = @attachment.extracted_texts.reorder(:created_at, :id).to_a
      assert_equal 2, records.size
      assert_equal "pdftotext", records.first.extractor_name
      assert_equal "empty", records.first.status
      assert_equal "ocrmypdf", records.second.extractor_name
      assert_equal "error", records.second.status
      assert_match(/ocrmypdf exploded/, records.second.error_message)
    end

    test "persists OCR result as 'empty' when OCR finds no text" do
      embedded_extractor = Class.new do
        def self.call(matter_attachment:)
          ExtractPdfText::Result.new(
            text: "",
            command_version: "pdftotext 24.02.0",
            extractor_name: ExtractPdfText::EXTRACTOR_NAME
          )
        end
      end
      ocr_extractor = Class.new do
        def self.call(matter_attachment:)
          OcrPdfText::Result.new(
            text: "",
            command_version: "ocrmypdf 16.10.0",
            extractor_name: OcrPdfText::EXTRACTOR_NAME
          )
        end
      end

      record = ExtractMatterAttachmentText.call(
        matter_attachment: @attachment,
        embedded_extractor:,
        ocr_extractor:
      )

      assert_equal "empty", record.status
      assert_equal OcrPdfText::EXTRACTOR_NAME, record.extractor_name
    end

    test "skips both extractors when a prior 'ok' extraction exists for the current checksum" do
      prior = @attachment.extracted_texts.create!(
        extractor_name: ExtractPdfText::EXTRACTOR_NAME,
        status: "ok",
        source_file_checksum_sha256: "deadbeef",
        content: "Already extracted text",
        character_count: 22
      )

      record = ExtractMatterAttachmentText.call(
        matter_attachment: @attachment,
        embedded_extractor: raising_extractor("embedded should not run"),
        ocr_extractor: raising_extractor("ocr should not run")
      )

      assert_equal prior.id, record.id
      assert_equal 1, @attachment.extracted_texts.count
    end

    test "skips OCR when a prior ocrmypdf 'empty' row exists for the current checksum" do
      prior = @attachment.extracted_texts.create!(
        extractor_name: OcrPdfText::EXTRACTOR_NAME,
        status: "empty",
        source_file_checksum_sha256: "deadbeef"
      )

      record = ExtractMatterAttachmentText.call(
        matter_attachment: @attachment,
        embedded_extractor: raising_extractor("embedded should not run"),
        ocr_extractor: raising_extractor("ocr should not run")
      )

      assert_equal prior.id, record.id
    end

    test "still runs OCR when only a prior pdftotext 'empty' row exists for the current checksum" do
      @attachment.extracted_texts.create!(
        extractor_name: ExtractPdfText::EXTRACTOR_NAME,
        status: "empty",
        source_file_checksum_sha256: "deadbeef"
      )

      embedded_extractor = Class.new do
        def self.call(matter_attachment:)
          ExtractPdfText::Result.new(
            text: "",
            command_version: "pdftotext 24.02.0",
            extractor_name: ExtractPdfText::EXTRACTOR_NAME
          )
        end
      end
      ocr_extractor = Class.new do
        def self.call(matter_attachment:)
          OcrPdfText::Result.new(
            text: "OCR recovered text",
            command_version: "ocrmypdf 16.10.0",
            extractor_name: OcrPdfText::EXTRACTOR_NAME
          )
        end
      end

      record = ExtractMatterAttachmentText.call(
        matter_attachment: @attachment,
        embedded_extractor:,
        ocr_extractor:
      )

      assert_equal "ok", record.status
      assert_equal OcrPdfText::EXTRACTOR_NAME, record.extractor_name
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

    def raising_extractor(message)
      Class.new do
        define_singleton_method(:call) { |matter_attachment:| raise message }
      end
    end

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
