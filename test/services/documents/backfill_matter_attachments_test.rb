require "test_helper"

module Documents
  class BackfillMatterAttachmentsTest < ActiveSupport::TestCase
    setup do
      @matter = Civic::Matter.create!(
        legistar_matter_id: 20_001,
        matter_file: "26-100",
        agenda_date: Date.new(2026, 5, 19)
      )
      @other_matter = Civic::Matter.create!(
        legistar_matter_id: 20_002,
        matter_file: "26-200",
        agenda_date: Date.new(2026, 6, 2)
      )
      clear_enqueued_jobs
    end

    test "dry run reports import and extraction candidates without enqueueing jobs" do
      import_candidate = attachment(@matter, 30_001, name: "Needs import", hyperlink: "https://sanjose.legistar.com/View.ashx?ID=1")
      extraction_candidate = imported_pdf_attachment(@matter, 30_002, name: "Needs extraction")
      already_done = imported_pdf_attachment(@matter, 30_003, name: "Already extracted")
      already_done.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "Done",
        character_count: 4
      )

      result = BackfillMatterAttachments.call(limit: 10, dry_run: true)

      assert_equal [ import_candidate.id ], result.import_candidates.map(&:id)
      assert_equal [ extraction_candidate.id ], result.extraction_candidates.map(&:id)
      assert_equal 0, result.import_enqueued
      assert_equal 0, result.extraction_enqueued
      assert_enqueued_jobs 0
    end

    test "enqueue mode dispatches import and extraction jobs" do
      import_candidate = attachment(@matter, 30_004, name: "Needs import", hyperlink: "https://sanjose.legistar.com/View.ashx?ID=2")
      extraction_candidate = imported_pdf_attachment(@matter, 30_005, name: "Needs extraction")

      result = nil
      assert_enqueued_jobs 1, only: Documents::ImportMatterAttachmentFileJob do
        assert_enqueued_jobs 1, only: Documents::ExtractMatterAttachmentTextJob do
          result = BackfillMatterAttachments.call(limit: 10, dry_run: false)
        end
      end

      assert_equal [ import_candidate.id ], result.import_candidates.map(&:id)
      assert_equal [ extraction_candidate.id ], result.extraction_candidates.map(&:id)
      assert_equal 1, result.import_enqueued
      assert_equal 1, result.extraction_enqueued
    end

    test "filters candidates by matter file and agenda date range" do
      included = attachment(@matter, 30_006, name: "Included", hyperlink: "https://sanjose.legistar.com/View.ashx?ID=3")
      attachment(@other_matter, 30_007, name: "Wrong matter", hyperlink: "https://sanjose.legistar.com/View.ashx?ID=4")

      result = BackfillMatterAttachments.call(
        limit: 10,
        dry_run: true,
        matter_file: "26-100",
        from_date: "2026-05-01",
        to_date: "2026-05-31"
      )

      assert_equal [ included.id ], result.import_candidates.map(&:id)
      assert_empty result.extraction_candidates
    end

    test "limit is shared across import and extraction candidates" do
      first = attachment(@matter, 30_008, name: "First import", hyperlink: "https://sanjose.legistar.com/View.ashx?ID=5")
      attachment(@matter, 30_009, name: "Second import", hyperlink: "https://sanjose.legistar.com/View.ashx?ID=6")
      imported_pdf_attachment(@matter, 30_010, name: "Extraction")

      result = BackfillMatterAttachments.call(limit: 1, dry_run: true)

      assert_equal [ first.id ], result.import_candidates.map(&:id)
      assert_empty result.extraction_candidates
    end

    test "extraction candidates ignore imported non-PDF attachments before applying the batch limit" do
      imported_text_attachment(@matter, 30_011, name: "Plain text")
      pdf = imported_pdf_attachment(@matter, 30_012, name: "PDF")

      result = BackfillMatterAttachments.call(limit: 1, dry_run: true)

      assert_empty result.import_candidates
      assert_equal [ pdf.id ], result.extraction_candidates.map(&:id)
    end

    test "import candidates skip attachments with prior import errors by default" do
      healthy = attachment(@matter, 30_013, name: "Healthy", hyperlink: "https://sanjose.legistar.com/View.ashx?ID=7")
      attachment(@matter, 30_014, name: "Errored", hyperlink: "https://sanjose.legistar.com/View.ashx?ID=8")
        .update!(source_file_import_error: "Net::HTTPNotFound: 404")

      result = BackfillMatterAttachments.call(limit: 10, dry_run: true)

      assert_equal [ healthy.id ], result.import_candidates.map(&:id)
    end

    test "retry_errors includes attachments with prior import errors" do
      healthy = attachment(@matter, 30_015, name: "Healthy", hyperlink: "https://sanjose.legistar.com/View.ashx?ID=9")
      errored = attachment(@matter, 30_016, name: "Errored", hyperlink: "https://sanjose.legistar.com/View.ashx?ID=10")
      errored.update!(source_file_import_error: "Net::HTTPNotFound: 404")

      result = BackfillMatterAttachments.call(limit: 10, dry_run: true, retry_errors: true)

      assert_equal [ healthy.id, errored.id ].sort, result.import_candidates.map(&:id).sort
    end

    test "invalid from_date raises a helpful error" do
      error = assert_raises(ArgumentError) do
        BackfillMatterAttachments.call(limit: 10, dry_run: true, from_date: "yesterday")
      end

      assert_match(/from_date must be a YYYY-MM-DD date/, error.message)
    end

    private

    def attachment(matter, legistar_id, name:, hyperlink: nil)
      matter.all_attachments.create!(
        legistar_matter_attachment_id: legistar_id,
        name:,
        hyperlink:
      )
    end

    def imported_pdf_attachment(matter, legistar_id, name:)
      attachment = attachment(matter, legistar_id, name:)
      attachment.source_file.attach(
        io: StringIO.new("%PDF-1.4 fake"),
        filename: "#{legistar_id}.pdf",
        content_type: "application/pdf"
      )
      attachment
    end

    def imported_text_attachment(matter, legistar_id, name:)
      attachment = attachment(matter, legistar_id, name:)
      attachment.source_file.attach(
        io: StringIO.new("plain text"),
        filename: "#{legistar_id}.txt",
        content_type: "text/plain"
      )
      attachment
    end
  end
end
