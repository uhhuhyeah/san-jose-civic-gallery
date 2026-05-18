require "test_helper"

module Documents
  class RevalidateMatterAttachmentFileTest < ActiveSupport::TestCase
    setup do
      matter = Civic::Matter.create!(legistar_matter_id: 15_886, matter_file: "26-575")
      @attachment = matter.all_attachments.create!(
        legistar_matter_attachment_id: 39_135,
        name: "Agreement",
        hyperlink: "https://sanjose.legistar.com/View.ashx?M=F&ID=1",
        source_file_byte_size: 100,
        source_file_etag: "\"old\"",
        source_file_last_modified_at: Time.zone.parse("2026-05-08 21:29:53"),
        source_file_final_url: "https://legistar.granicus.com/file.pdf"
      )
      @attachment.source_file.attach(
        io: StringIO.new("%PDF-1.4 old"),
        filename: "agreement.pdf",
        content_type: "application/pdf"
      )
      clear_enqueued_jobs
    end

    test "marks not modified attachments as validated" do
      probe = probe_returning(RemoteFileProbe::Result.new(
        status: :not_modified,
        final_url: "https://legistar.granicus.com/file.pdf",
        etag: "\"old\""
      ))

      result = RevalidateMatterAttachmentFile.call(matter_attachment: @attachment, probe:)

      assert_equal :unchanged, result.action
      assert_not_nil @attachment.reload.source_file_validated_at
      assert_nil @attachment.source_file_validation_error
    end

    test "marks matching metadata as validated without import" do
      probe = probe_returning(RemoteFileProbe::Result.new(
        status: :ok,
        final_url: "https://legistar.granicus.com/file.pdf",
        content_length: 100,
        etag: "\"old\""
      ))
      importer = Class.new do
        def self.call(matter_attachment:)
          raise "should not import"
        end
      end

      result = RevalidateMatterAttachmentFile.call(matter_attachment: @attachment, probe:, importer:)

      assert_equal :unchanged, result.action
      assert_not_nil @attachment.reload.source_file_validated_at
    end

    test "reimports and enqueues extraction when remote metadata differs" do
      probe = probe_returning(RemoteFileProbe::Result.new(
        status: :ok,
        final_url: "https://legistar.granicus.com/file.pdf",
        content_length: 101,
        etag: "\"new\"",
        last_modified_at: Time.zone.parse("2026-05-09 21:29:53")
      ))
      importer = Class.new do
        def self.call(matter_attachment:)
          matter_attachment.update!(
            source_file_byte_size: 101,
            source_file_etag: "\"new\"",
            source_file_validated_at: Time.current,
            source_file_validation_error: nil
          )
        end
      end

      result = nil
      assert_enqueued_jobs 1, only: Documents::ExtractMatterAttachmentTextJob do
        result = RevalidateMatterAttachmentFile.call(matter_attachment: @attachment, probe:, importer:)
      end

      assert_equal :reimported, result.action
      assert_equal 101, @attachment.reload.source_file_byte_size
      assert_equal "\"new\"", @attachment.source_file_etag
    end

    test "treats differing etag as changed even when byte size matches" do
      probe = probe_returning(RemoteFileProbe::Result.new(
        status: :ok,
        final_url: "https://legistar.granicus.com/file.pdf",
        content_length: 100,
        etag: "\"new\""
      ))
      importer = Class.new do
        def self.call(matter_attachment:)
          matter_attachment.update!(
            source_file_etag: "\"new\"",
            source_file_validated_at: Time.current,
            source_file_validation_error: nil
          )
        end
      end

      result = RevalidateMatterAttachmentFile.call(matter_attachment: @attachment, probe:, importer:)

      assert_equal :reimported, result.action
      assert_equal "\"new\"", @attachment.reload.source_file_etag
    end

    test "records validation errors and re-raises" do
      probe = Class.new do
        def self.call(**)
          raise SafeDownloader::HttpError, "HTTP 500"
        end
      end

      assert_raises(SafeDownloader::HttpError) do
        RevalidateMatterAttachmentFile.call(matter_attachment: @attachment, probe:)
      end

      assert_match(/HTTP 500/, @attachment.reload.source_file_validation_error)
    end

    test "probes the canonical hyperlink rather than the saved final_url" do
      captured = []
      probe = Class.new do
        define_singleton_method(:call) do |url:, **_kwargs|
          captured << url
          RemoteFileProbe::Result.new(status: :not_modified, final_url: url, etag: "\"old\"")
        end
      end

      RevalidateMatterAttachmentFile.call(matter_attachment: @attachment, probe:)

      assert_equal [ @attachment.hyperlink ], captured
    end

    test "treats absence of validators on both sides as unchanged" do
      @attachment.update!(
        source_file_byte_size: nil,
        source_file_etag: nil,
        source_file_last_modified_at: nil,
        source_file_validated_at: nil
      )
      probe = probe_returning(RemoteFileProbe::Result.new(
        status: :ok,
        final_url: "https://legistar.granicus.com/file.pdf"
      ))
      importer = Class.new do
        def self.call(matter_attachment:)
          raise "should not import when no validators are comparable"
        end
      end

      result = RevalidateMatterAttachmentFile.call(matter_attachment: @attachment, probe:, importer:)

      assert_equal :unchanged, result.action
      assert_not_nil @attachment.reload.source_file_validated_at
    end

    test "supersedes prior extracted_text rows when reimporting" do
      prior_ok = @attachment.extracted_texts.create!(extractor_name: "pdftotext", status: "ok", content: "old")
      prior_empty = @attachment.extracted_texts.create!(extractor_name: "pdftotext", status: "empty")
      prior_error = @attachment.extracted_texts.create!(extractor_name: "pdftotext", status: "error", error_message: "boom")

      probe = probe_returning(RemoteFileProbe::Result.new(
        status: :ok,
        final_url: "https://legistar.granicus.com/file.pdf",
        content_length: 101,
        etag: "\"new\""
      ))
      importer = Class.new do
        def self.call(matter_attachment:)
          matter_attachment.update!(source_file_byte_size: 101, source_file_etag: "\"new\"")
        end
      end

      RevalidateMatterAttachmentFile.call(matter_attachment: @attachment, probe:, importer:)

      assert_equal "superseded", prior_ok.reload.status
      assert_equal "superseded", prior_empty.reload.status
      assert_equal "error", prior_error.reload.status
    end

    test "reimport that downgrades to non-PDF skips extraction and supersedes prior text" do
      prior_ok = @attachment.extracted_texts.create!(extractor_name: "pdftotext", status: "ok", content: "old PDF")

      probe = probe_returning(RemoteFileProbe::Result.new(
        status: :ok,
        final_url: "https://legistar.granicus.com/file.txt",
        content_length: 50,
        etag: "\"new\""
      ))
      importer = Class.new do
        def self.call(matter_attachment:)
          matter_attachment.source_file.purge
          matter_attachment.source_file.attach(
            io: StringIO.new("plain text"),
            filename: "file.txt",
            content_type: "text/plain"
          )
          matter_attachment.update!(source_file_byte_size: 50, source_file_etag: "\"new\"")
        end
      end

      result = nil
      assert_no_enqueued_jobs only: Documents::ExtractMatterAttachmentTextJob do
        result = RevalidateMatterAttachmentFile.call(matter_attachment: @attachment, probe:, importer:)
      end

      assert_equal :reimported, result.action
      assert_equal "superseded", prior_ok.reload.status
      assert_not @attachment.reload.extractable_as_pdf?
    end

    private

    def probe_returning(result)
      Class.new do
        define_singleton_method(:call) do |**_kwargs|
          result
        end
      end
    end
  end
end
