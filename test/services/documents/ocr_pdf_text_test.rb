require "test_helper"

module Documents
  class OcrPdfTextTest < ActiveSupport::TestCase
    setup do
      matter = Civic::Matter.create!(
        legistar_matter_id: 15886,
        matter_file: "26-575"
      )
      @attachment = Civic::MatterAttachment.create!(
        civic_matter_id: matter.id,
        legistar_matter_attachment_id: 39135,
        name: "Scanned agreement"
      )
      @attachment.source_file.attach(
        io: StringIO.new("%PDF-1.4 scanned"),
        filename: "scanned-agreement.pdf",
        content_type: "application/pdf"
      )
    end

    test "extracts OCR sidecar text and reports the command version" do
      stub_run_ocr { |sidecar_path:, **_| File.write(sidecar_path, "OCR body text") }
      stub_capture_version("ocrmypdf 16.10.0")

      result = OcrPdfText.call(matter_attachment: @attachment)

      assert_equal "OCR body text", result.text
      assert_equal "ocrmypdf 16.10.0", result.command_version
      assert_equal OcrPdfText::EXTRACTOR_NAME, result.extractor_name
    end

    test "returns an empty sidecar text without raising when OCR finds nothing" do
      stub_run_ocr { |sidecar_path:, **_| File.write(sidecar_path, "") }
      stub_capture_version("ocrmypdf 16.10.0")

      result = OcrPdfText.call(matter_attachment: @attachment)

      assert_equal "", result.text
    end

    test "raises a clear error when ocrmypdf fails" do
      stub_run_ocr { |**_| raise "ocrmypdf failed: bad scan" }

      error = assert_raises(RuntimeError) do
        OcrPdfText.call(matter_attachment: @attachment)
      end

      assert_match(/ocrmypdf failed: bad scan/, error.message)
    end

    test "translates missing-binary SystemCallError into a friendly unavailable message" do
      stub_run_ocr { |**_| raise Errno::ENOENT, "ocrmypdf" }

      error = assert_raises(RuntimeError) do
        OcrPdfText.call(matter_attachment: @attachment)
      end

      assert_match(/ocrmypdf unavailable/, error.message)
    end

    test "translates permission-denied SystemCallError into a friendly unavailable message" do
      stub_run_ocr { |**_| raise Errno::EACCES, "ocrmypdf" }

      error = assert_raises(RuntimeError) do
        OcrPdfText.call(matter_attachment: @attachment)
      end

      assert_match(/ocrmypdf unavailable/, error.message)
    end

    private

    def stub_run_ocr(&block)
      original = OcrPdfText.method(:run_ocr)
      OcrPdfText.define_singleton_method(:run_ocr, &block)
      @run_ocr_restorer = -> { OcrPdfText.define_singleton_method(:run_ocr, original) }
    end

    def stub_capture_version(version)
      original = OcrPdfText.method(:capture_version)
      OcrPdfText.define_singleton_method(:capture_version) { |_command| version }
      @capture_version_restorer = -> { OcrPdfText.define_singleton_method(:capture_version, original) }
    end

    def teardown
      @run_ocr_restorer&.call
      @capture_version_restorer&.call
    end
  end
end
