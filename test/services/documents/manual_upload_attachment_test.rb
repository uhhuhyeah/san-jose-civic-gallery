require "test_helper"
require "tempfile"

module Documents
  class ManualUploadAttachmentTest < ActiveSupport::TestCase
    setup do
      matter = Civic::Matter.create!(legistar_matter_id: 99_001, matter_file: "26-999")
      @attachment = matter.all_attachments.create!(
        legistar_matter_attachment_id: 99_002,
        name: "2026-2027 Proposed Capital Budget",
        hyperlink: "https://www.sanjoseca.gov/your-government/.../capital-budget",
        source_file_import_error: "Documents::SafeHttpClient::HttpError: HTTP 403"
      )

      @pdf = Tempfile.new([ "manual-upload-test", ".pdf" ])
      @pdf.binmode
      @pdf.write("%PDF-1.4\n% test\n%%EOF\n")
      @pdf.rewind

      clear_enqueued_jobs
    end

    teardown do
      @pdf.close
      @pdf.unlink
    end

    test "attaches the PDF, stamps source metadata, and records the manual import" do
      ManualUploadAttachment.call(
        attachment_id: @attachment.id,
        pdf_path: @pdf.path,
        operator: "david@civicgallery.org",
        reason: "Akamai blocks the source URL"
      )

      @attachment.reload
      assert @attachment.source_file.attached?
      assert_equal "application/pdf", @attachment.source_file.content_type
      assert @attachment.source_file_byte_size.positive?
      assert_match(/\A[0-9a-f]{64}\z/, @attachment.source_file_checksum_sha256)
      assert_not_nil @attachment.source_file_imported_at
      assert_equal @attachment.hyperlink, @attachment.source_file_final_url
      assert @attachment.manually_imported?
      assert_equal "david@civicgallery.org", @attachment.manually_imported_by
      assert_equal "Akamai blocks the source URL", @attachment.manual_import_reason
      assert_nil @attachment.source_file_import_error
    end

    test "enqueues text extraction after attaching the file" do
      assert_enqueued_with(job: Documents::ExtractMatterAttachmentTextJob, args: [ @attachment.id ]) do
        ManualUploadAttachment.call(
          attachment_id: @attachment.id,
          pdf_path: @pdf.path,
          operator: "operator@example.com",
          reason: "test"
        )
      end
    end

    test "raises AttachmentNotFound for an unknown attachment id" do
      assert_raises(ManualUploadAttachment::AttachmentNotFound) do
        ManualUploadAttachment.call(
          attachment_id: 0,
          pdf_path: @pdf.path,
          operator: "x@y.z",
          reason: "x"
        )
      end
    end

    test "raises PdfNotFound when the file path does not exist" do
      assert_raises(ManualUploadAttachment::PdfNotFound) do
        ManualUploadAttachment.call(
          attachment_id: @attachment.id,
          pdf_path: "/tmp/this-file-does-not-exist-#{SecureRandom.hex(4)}.pdf",
          operator: "x@y.z",
          reason: "x"
        )
      end
    end

    test "raises NotAPdf when the file is not application/pdf" do
      html = Tempfile.new([ "not-a-pdf", ".html" ])
      html.binmode
      html.write("<!DOCTYPE html><html><body>hi</body></html>")
      html.rewind

      assert_raises(ManualUploadAttachment::NotAPdf) do
        ManualUploadAttachment.call(
          attachment_id: @attachment.id,
          pdf_path: html.path,
          operator: "x@y.z",
          reason: "x"
        )
      end
    ensure
      html&.close
      html&.unlink
    end
  end
end
