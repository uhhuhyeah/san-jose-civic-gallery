require "test_helper"

module Documents
  class ImportMatterAttachmentFileTest < ActiveSupport::TestCase
    setup do
      @matter = Civic::Matter.create!(
        legistar_matter_id: 15886,
        matter_file: "26-575"
      )
      @attachment = Civic::MatterAttachment.create!(
        civic_matter_id: @matter.id,
        legistar_matter_attachment_id: 39135,
        name: "Agreement",
        hyperlink: "https://example.test/agreement.pdf",
        file_name: "agreement.pdf"
      )
    end

    test "imports the remote file into active storage" do
      fake_pdf = "%PDF-1.4 test"
      fake_io = StringIO.new(fake_pdf)
      original_open = URI.method(:open)

      URI.define_singleton_method(:open) do |*_args|
        fake_io.rewind
        fake_io
      end

      begin
        ImportMatterAttachmentFile.call(matter_attachment: @attachment)
      ensure
        URI.define_singleton_method(:open, original_open)
      end

      @attachment.reload

      assert @attachment.source_file.attached?
      assert_equal fake_pdf.bytesize, @attachment.source_file_byte_size
      assert_nil @attachment.source_file_import_error
      assert_not_nil @attachment.source_file_imported_at
    end
  end
end
