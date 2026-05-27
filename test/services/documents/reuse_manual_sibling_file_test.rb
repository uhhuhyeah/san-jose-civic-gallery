require "test_helper"
require "stringio"

module Documents
  class ReuseManualSiblingFileTest < ActiveSupport::TestCase
    setup do
      @matter = Civic::Matter.create!(legistar_matter_id: 70_001, matter_file: "26-700")
      @hyperlink = "https://www.sanjoseca.gov/your-government/budget/proposed-fees"
      @sibling_body = "%PDF-1.4 reused sibling\n%%EOF\n"
    end

    test "copies the manually uploaded sibling file across and stamps a manual import" do
      sibling = create_manual_sibling(legistar_id: 70_002, operator: "operator@example.com")
      target = create_blocked_attachment(legistar_id: 70_003)

      result = ReuseManualSiblingFile.call(matter_attachment: target)

      assert_equal target, result
      target.reload

      assert target.source_file.attached?
      assert_equal "application/pdf", target.source_file.content_type
      assert_equal @sibling_body.bytesize, target.source_file_byte_size
      assert_equal sibling.source_file_checksum_sha256, target.source_file_checksum_sha256
      assert_nil target.source_file_import_error
      assert_equal @hyperlink, target.source_file_final_url
      assert target.manually_imported?
      assert_equal "operator@example.com", target.manually_imported_by
      assert_match(/Reused operator upload from attachment ##{sibling.id}/, target.manual_import_reason)
    end

    test "returns nil when no manually uploaded sibling shares the hyperlink" do
      target = create_blocked_attachment(legistar_id: 70_003)

      assert_nil ReuseManualSiblingFile.call(matter_attachment: target)

      target.reload
      assert_not target.source_file.attached?
    end

    test "ignores siblings with a different hyperlink" do
      sibling = create_manual_sibling(legistar_id: 70_002, operator: "operator@example.com")
      sibling.update!(hyperlink: "https://www.sanjoseca.gov/other-document")
      target = create_blocked_attachment(legistar_id: 70_003)

      assert_nil ReuseManualSiblingFile.call(matter_attachment: target)
    end

    private

    def create_manual_sibling(legistar_id:, operator:)
      sibling = Civic::MatterAttachment.create!(
        civic_matter_id: @matter.id,
        legistar_matter_attachment_id: legistar_id,
        name: "Proposed Fees (sibling)",
        hyperlink: @hyperlink,
        file_name: "fees.pdf"
      )
      sibling.source_file.attach(
        io: StringIO.new(@sibling_body),
        filename: "fees.pdf",
        content_type: "application/pdf"
      )
      sibling.update!(
        source_file_imported_at: Time.current,
        source_file_checksum_sha256: Digest::SHA256.hexdigest(@sibling_body),
        source_file_byte_size: @sibling_body.bytesize,
        manually_imported_at: Time.current,
        manually_imported_by: operator,
        manual_import_reason: "Akamai blocks the source URL"
      )
      sibling
    end

    def create_blocked_attachment(legistar_id:)
      Civic::MatterAttachment.create!(
        civic_matter_id: @matter.id,
        legistar_matter_attachment_id: legistar_id,
        name: "Proposed Fees",
        hyperlink: @hyperlink,
        file_name: "fees.pdf",
        source_file_import_error: "Documents::SafeHttpClient::HttpError: HTTP 403 from #{@hyperlink}"
      )
    end
  end
end
