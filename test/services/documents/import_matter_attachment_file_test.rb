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

    test "raises ArgumentError when the hyperlink is missing" do
      @attachment.update!(hyperlink: nil)

      assert_raises(ArgumentError) do
        ImportMatterAttachmentFile.call(matter_attachment: @attachment)
      end
    end

    private

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
