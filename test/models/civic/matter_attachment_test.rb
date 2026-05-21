require "test_helper"

module Civic
  class MatterAttachmentTest < ActiveSupport::TestCase
    setup do
      @matter = Matter.create!(
        legistar_matter_id: 15915,
        matter_file: "26-602"
      )
    end

    test "requires source_attachment_id and name" do
      attachment = MatterAttachment.new(matter: @matter)

      assert_not attachment.valid?
      assert_includes attachment.errors[:source_attachment_id], "can't be blank"
      assert_includes attachment.errors[:name], "can't be blank"
    end

    test "awaiting_file returns attachments with no stored file and no manual upload" do
      without_file = @matter.all_attachments.create!(legistar_matter_attachment_id: 4001, name: "No file")
      with_file = @matter.all_attachments.create!(legistar_matter_attachment_id: 4002, name: "Has file")
      with_file.source_file.attach(io: StringIO.new("%PDF-1.4 x"), filename: "a.pdf", content_type: "application/pdf")
      manually = @matter.all_attachments.create!(legistar_matter_attachment_id: 4003, name: "Manual", manually_imported_at: Time.current)

      awaiting = Civic::MatterAttachment.awaiting_file
      assert_includes awaiting, without_file
      assert_not_includes awaiting, with_file
      assert_not_includes awaiting, manually
    end

    test "imported scope returns attachments with a recorded import timestamp" do
      not_yet = @matter.all_attachments.create!(legistar_matter_attachment_id: 7001, name: "Pending")
      imported = @matter.all_attachments.create!(
        legistar_matter_attachment_id: 7002,
        name: "Imported",
        source_file_imported_at: Time.current
      )

      ids = MatterAttachment.imported.pluck(:id)
      assert_includes ids, imported.id
      assert_not_includes ids, not_yet.id
    end

    test "needs_manual_upload scope returns attachments with import errors and no manual upload yet" do
      clean = @matter.all_attachments.create!(
        legistar_matter_attachment_id: 8001,
        name: "Clean"
      )
      needs_help = @matter.all_attachments.create!(
        legistar_matter_attachment_id: 8002,
        name: "Akamai-blocked",
        source_file_import_error: "Documents::SafeHttpClient::HttpError: HTTP 403"
      )
      already_resolved = @matter.all_attachments.create!(
        legistar_matter_attachment_id: 8003,
        name: "Manually fixed",
        source_file_import_error: "Documents::SafeHttpClient::HttpError: HTTP 403",
        manually_imported_at: Time.current,
        manually_imported_by: "operator@example.com"
      )

      ids = MatterAttachment.needs_manual_upload.pluck(:id)
      assert_includes ids, needs_help.id
      assert_not_includes ids, clean.id
      assert_not_includes ids, already_resolved.id
    end
  end
end
