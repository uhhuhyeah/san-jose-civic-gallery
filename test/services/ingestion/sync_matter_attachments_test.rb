require "test_helper"

module Ingestion
  class SyncMatterAttachmentsTest < ActiveSupport::TestCase
    setup do
      @matter = Civic::Matter.create!(
        legistar_matter_id: 15886,
        matter_file: "26-575"
      )
      @stale_attachment = @matter.all_attachments.create!(
        legistar_matter_attachment_id: 333,
        name: "Removed attachment",
        hyperlink: "https://example.test/removed.pdf"
      )
      clear_enqueued_jobs
    end

    test "reconciles missing attachments and enqueues file import for current ones" do
      client = Class.new do
        def matter_attachments(matter_id:)
          raise "unexpected matter_id" unless matter_id == 15886

          {
            request_url: "https://example.test/Matters/15886/Attachments",
            status: 200,
            fetched_at: Time.zone.parse("2026-05-15 11:00:00"),
            response_sha256: "attachment-sha",
            payload: [
              {
                "MatterAttachmentId" => 39135,
                "MatterAttachmentName" => "Agreement",
                "MatterAttachmentHyperlink" => "https://example.test/agreement.pdf",
                "MatterAttachmentFileName" => "agreement.pdf",
                "MatterAttachmentMatterVersion" => "0",
                "MatterAttachmentIsHyperlink" => false,
                "MatterAttachmentIsSupportingDocument" => false,
                "MatterAttachmentShowOnInternetPage" => true,
                "MatterAttachmentIsMinuteOrder" => false,
                "MatterAttachmentIsBoardLetter" => false,
                "MatterAttachmentDescription" => nil,
                "MatterAttachmentPrintWithReports" => true,
                "MatterAttachmentSort" => 5,
                "MatterAttachmentLastModifiedUtc" => "2026-05-15T10:30:00Z"
              }
            ]
          }
        end
      end.new

      assert_enqueued_jobs 1, only: Documents::ImportMatterAttachmentFileJob do
        SyncMatterAttachments.call(matter: @matter, client:, import_files: :deferred)
      end

      @stale_attachment.reload
      assert_not @stale_attachment.source_present
      assert_equal Time.zone.parse("2026-05-15 11:00:00"), @stale_attachment.source_missing_at

      current_attachment = @matter.attachments.find_by!(legistar_matter_attachment_id: 39135)
      assert current_attachment.source_present
      enqueued_attachment_ids = enqueued_jobs.to_a.filter_map do |job|
        next unless job.fetch("job_class") == "Documents::ImportMatterAttachmentFileJob"

        job.fetch("arguments").first
      end

      assert_equal [ current_attachment.id ], enqueued_attachment_ids
    end
  end
end
