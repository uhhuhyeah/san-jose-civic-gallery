require "test_helper"

module Documents
  class BackfillAttachmentRevalidationsTest < ActiveSupport::TestCase
    setup do
      @matter = Civic::Matter.create!(legistar_matter_id: 15_886, matter_file: "26-575")
      clear_enqueued_jobs
    end

    test "dry run reports due imported attachments without enqueueing jobs" do
      due = imported_attachment(39_135, validated_at: 45.days.ago)
      imported_attachment(39_136, validated_at: 1.day.ago)
      not_imported = @matter.all_attachments.create!(
        legistar_matter_attachment_id: 39_137,
        name: "Not imported",
        hyperlink: "https://sanjose.legistar.com/View.ashx?ID=3"
      )

      result = BackfillAttachmentRevalidations.call(limit: 10, dry_run: true)

      assert_equal [ due.id ], result.candidates.map(&:id)
      assert_equal 0, result.enqueued
      assert_enqueued_jobs 0
      assert_not not_imported.source_file.attached?
    end

    test "enqueue mode dispatches revalidation jobs" do
      due = imported_attachment(39_138, validated_at: nil)

      result = nil
      assert_enqueued_jobs 1, only: Documents::RevalidateMatterAttachmentFileJob do
        result = BackfillAttachmentRevalidations.call(limit: 10, dry_run: false)
      end

      assert_equal [ due.id ], result.candidates.map(&:id)
      assert_equal 1, result.enqueued
    end

    test "skips attachments with prior validation errors by default" do
      due = imported_attachment(39_139, validated_at: 45.days.ago)
      errored = imported_attachment(39_140, validated_at: 45.days.ago)
      errored.update!(source_file_validation_error: "Net::HTTPNotFound: 404")

      result = BackfillAttachmentRevalidations.call(limit: 10, dry_run: true)

      assert_equal [ due.id ], result.candidates.map(&:id)
    end

    test "retry_errors includes attachments whose previous revalidation failed" do
      due = imported_attachment(39_141, validated_at: 45.days.ago)
      errored = imported_attachment(39_142, validated_at: 45.days.ago)
      errored.update!(source_file_validation_error: "Net::HTTPNotFound: 404")

      result = BackfillAttachmentRevalidations.call(limit: 10, dry_run: true, retry_errors: true)

      assert_equal [ due.id, errored.id ].sort, result.candidates.map(&:id).sort
    end

    private

    def imported_attachment(legistar_id, validated_at:)
      attachment = @matter.all_attachments.create!(
        legistar_matter_attachment_id: legistar_id,
        name: "Imported #{legistar_id}",
        hyperlink: "https://sanjose.legistar.com/View.ashx?ID=#{legistar_id}",
        source_file_imported_at: 2.months.ago,
        source_file_validated_at: validated_at
      )
      attachment.source_file.attach(
        io: StringIO.new("%PDF-1.4 fake"),
        filename: "#{legistar_id}.pdf",
        content_type: "application/pdf"
      )
      attachment
    end
  end
end
