require "test_helper"
require "stringio"

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
        hyperlink: "https://sanjose.legistar.com/View.ashx?M=F&ID=1",
        file_name: "agreement.pdf"
      )
    end

    test "imports the remote file into active storage" do
      body = "%PDF-1.4 test"
      downloader = build_downloader(body: body, content_type: "application/pdf")

      ImportMatterAttachmentFile.call(matter_attachment: @attachment, downloader: downloader)

      @attachment.reload

      assert @attachment.source_file.attached?
      assert_equal body.bytesize, @attachment.source_file_byte_size
      assert_equal Digest::SHA256.hexdigest(body), @attachment.source_file_checksum_sha256
      assert_nil @attachment.source_file_import_error
      assert_not_nil @attachment.source_file_imported_at
      assert_not_nil @attachment.source_file_validated_at
      assert_equal "agreement.pdf", @attachment.source_file.filename.to_s
      assert_equal "application/pdf", @attachment.source_file.content_type
    end

    test "infers a filename with extension when file_name is blank" do
      @attachment.update!(file_name: nil)
      downloader = build_downloader(body: "%PDF-1.4 inferred", content_type: "application/pdf")

      ImportMatterAttachmentFile.call(matter_attachment: @attachment, downloader: downloader)

      @attachment.reload

      assert_equal "39135-attachment.pdf", @attachment.source_file.filename.to_s
    end

    test "records the error on failure and re-raises" do
      failing_downloader = Class.new do
        def self.call(url:, io:)
          raise SafeDownloader::DisallowedHostError, "boom"
        end
      end

      assert_raises(SafeDownloader::DisallowedHostError) do
        ImportMatterAttachmentFile.call(matter_attachment: @attachment, downloader: failing_downloader)
      end

      @attachment.reload
      assert_not @attachment.source_file.attached?
      assert_match(/DisallowedHostError/, @attachment.source_file_import_error)
    end

    test "reuses a manually uploaded sibling file after a 403 instead of re-raising" do
      sibling_body = "%PDF-1.4 sibling\n%%EOF\n"
      sibling = Civic::MatterAttachment.create!(
        civic_matter_id: @matter.id,
        legistar_matter_attachment_id: 39_999,
        name: "Agreement (sibling)",
        hyperlink: @attachment.hyperlink,
        file_name: "agreement.pdf"
      )
      sibling.source_file.attach(
        io: StringIO.new(sibling_body),
        filename: "agreement.pdf",
        content_type: "application/pdf"
      )
      sibling.update!(
        source_file_imported_at: Time.current,
        source_file_checksum_sha256: Digest::SHA256.hexdigest(sibling_body),
        source_file_byte_size: sibling_body.bytesize,
        manually_imported_at: Time.current,
        manually_imported_by: "operator@example.com",
        manual_import_reason: "Akamai blocks the source URL"
      )

      result = ImportMatterAttachmentFile.call(
        matter_attachment: @attachment,
        downloader: failing_downloader(status: 403)
      )

      assert_equal @attachment, result
      @attachment.reload
      assert @attachment.source_file.attached?
      assert_equal Digest::SHA256.hexdigest(sibling_body), @attachment.source_file_checksum_sha256
      assert @attachment.manually_imported?
      assert_equal "operator@example.com", @attachment.manually_imported_by
      assert_nil @attachment.source_file_import_error
    end

    test "records the original error and re-raises when the reuse attempt itself fails" do
      sibling = Civic::MatterAttachment.create!(
        civic_matter_id: @matter.id,
        legistar_matter_attachment_id: 39_997,
        name: "Agreement (sibling)",
        hyperlink: @attachment.hyperlink,
        file_name: "agreement.pdf"
      )
      sibling.source_file.attach(
        io: StringIO.new("%PDF-1.4 sibling\n%%EOF\n"),
        filename: "agreement.pdf",
        content_type: "application/pdf"
      )
      sibling.update!(manually_imported_at: Time.current, manually_imported_by: "operator@example.com")

      # Drop the sibling's stored file (keeping its DB rows) so copying it
      # raises, exercising the fall-through that preserves the original error.
      blob = sibling.source_file.blob
      blob.service.delete(blob.key)

      assert_raises(SafeHttpClient::HttpError) do
        ImportMatterAttachmentFile.call(
          matter_attachment: @attachment,
          downloader: failing_downloader(status: 403)
        )
      end

      @attachment.reload
      assert_not @attachment.source_file.attached?
      assert_match(/HTTP 403/, @attachment.source_file_import_error)
    end

    test "records the error and re-raises on a 403 when no reusable sibling exists" do
      assert_raises(SafeHttpClient::HttpError) do
        ImportMatterAttachmentFile.call(
          matter_attachment: @attachment,
          downloader: failing_downloader(status: 403)
        )
      end

      @attachment.reload
      assert_not @attachment.source_file.attached?
      assert_match(/HTTP 403/, @attachment.source_file_import_error)
    end

    test "does not reuse a sibling for a non-access-blocked HTTP error" do
      sibling = Civic::MatterAttachment.create!(
        civic_matter_id: @matter.id,
        legistar_matter_attachment_id: 39_998,
        name: "Agreement (sibling)",
        hyperlink: @attachment.hyperlink,
        file_name: "agreement.pdf"
      )
      sibling.source_file.attach(
        io: StringIO.new("%PDF-1.4 sibling\n%%EOF\n"),
        filename: "agreement.pdf",
        content_type: "application/pdf"
      )
      sibling.update!(manually_imported_at: Time.current, manually_imported_by: "operator@example.com")

      assert_raises(SafeHttpClient::HttpError) do
        ImportMatterAttachmentFile.call(
          matter_attachment: @attachment,
          downloader: failing_downloader(status: 404)
        )
      end

      @attachment.reload
      assert_not @attachment.source_file.attached?
      assert_match(/HTTP 404/, @attachment.source_file_import_error)
    end

    test "raises ArgumentError when the hyperlink is missing" do
      @attachment.update!(hyperlink: nil)

      assert_raises(ArgumentError) do
        ImportMatterAttachmentFile.call(matter_attachment: @attachment)
      end
    end

    private

    def failing_downloader(status:)
      Class.new do
        define_singleton_method(:call) do |url:, io:|
          raise Documents::SafeHttpClient::HttpError.new("HTTP #{status} from #{url}", status: status)
        end
      end
    end

    def build_downloader(body:, content_type:)
      Class.new do
        define_singleton_method(:call) do |url:, io:|
          io.write(body)
          io.flush
          SafeDownloader::Result.new(
            checksum_sha256: Digest::SHA256.hexdigest(body),
            byte_size: body.bytesize,
            content_type: content_type,
            final_url: url,
            etag: "\"abc\"",
            last_modified_at: Time.zone.parse("2026-05-08 21:29:53")
          )
        end
      end
    end
  end
end
