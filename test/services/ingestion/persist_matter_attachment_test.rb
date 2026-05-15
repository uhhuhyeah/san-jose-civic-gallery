require "test_helper"

module Ingestion
  class PersistMatterAttachmentTest < ActiveSupport::TestCase
    setup do
      @matter = Civic::Matter.create!(
        legistar_matter_id: 15886,
        matter_file: "26-575"
      )
    end

    test "persists a matter attachment and raw snapshot" do
      payload = {
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
        "MatterAttachmentLastModifiedUtc" => "2026-05-14T19:46:47.76"
      }

      attachment, snapshot = PersistMatterAttachment.call(
        matter: @matter,
        attachment_payload: payload,
        source_system: "legistar.sanjose",
        request_url: "https://example.test/Matters/15886/Attachments",
        fetched_at: Time.zone.parse("2026-05-15 09:00:00"),
        http_status: 200,
        response_sha256: "jkl012"
      )

      assert_equal 39135, attachment.legistar_matter_attachment_id
      assert_equal @matter.id, attachment.civic_matter_id
      assert_equal "Agreement", attachment.name
      assert_equal "matter_attachment", snapshot.resource_type
      assert_equal "39135", snapshot.source_id
      assert_equal "legistar.sanjose", attachment.source_system
      assert_equal snapshot.id, attachment.last_source_snapshot_id
    end
  end
end
