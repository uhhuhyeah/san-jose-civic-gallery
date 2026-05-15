require "test_helper"

module Documents
  class ExtractPdfTextTest < ActiveSupport::TestCase
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
      @attachment.source_file.attach(
        io: StringIO.new("%PDF-1.4 fake"),
        filename: "agreement.pdf",
        content_type: "application/pdf"
      )
    end

    test "extracts text with pdftotext command wrapper" do
      fake_status = Struct.new(:success?).new(true)
      original_capture3 = Open3.method(:capture3)
      original_capture2 = Open3.method(:capture2)
      original_file_read = File.method(:read)

      Open3.define_singleton_method(:capture3) { |*_args| ["", "", fake_status] }
      Open3.define_singleton_method(:capture2) { |*_args| ["pdftotext 24.02.0\n", fake_status] }
      File.define_singleton_method(:read) { |_path| "Extracted body text" }

      result = ExtractPdfText.call(matter_attachment: @attachment)

      assert_equal "Extracted body text", result.text
      assert_equal "pdftotext 24.02.0", result.command_version
    ensure
      Open3.define_singleton_method(:capture3, original_capture3)
      Open3.define_singleton_method(:capture2, original_capture2)
      File.define_singleton_method(:read, original_file_read)
    end
  end
end
