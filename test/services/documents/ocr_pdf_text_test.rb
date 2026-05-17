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

    test "extracts OCR sidecar text with ocrmypdf command wrapper" do
      fake_status = Struct.new(:success?).new(true)
      original_capture3 = Open3.method(:capture3)
      original_file_read = File.method(:read)

      Open3.define_singleton_method(:capture3) do |*args|
        if args == [ "ocrmypdf", "--version" ]
          [ "ocrmypdf 16.10.0\n", "", fake_status ]
        else
          [ "", "", fake_status ]
        end
      end
      File.define_singleton_method(:read) { |_path| "OCR body text" }

      result = OcrPdfText.call(matter_attachment: @attachment)

      assert_equal "OCR body text", result.text
      assert_equal "ocrmypdf 16.10.0", result.command_version
      assert_equal "ocrmypdf", result.extractor_name
    ensure
      Open3.define_singleton_method(:capture3, original_capture3)
      File.define_singleton_method(:read, original_file_read)
    end

    test "raises a clear error when ocrmypdf fails" do
      fake_status = Struct.new(:success?).new(false)
      original_capture3 = Open3.method(:capture3)

      Open3.define_singleton_method(:capture3) do |*_args|
        [ "", "bad scan", fake_status ]
      end

      error = assert_raises(RuntimeError) do
        OcrPdfText.call(matter_attachment: @attachment)
      end

      assert_match(/ocrmypdf failed: bad scan/, error.message)
    ensure
      Open3.define_singleton_method(:capture3, original_capture3)
    end
  end
end
