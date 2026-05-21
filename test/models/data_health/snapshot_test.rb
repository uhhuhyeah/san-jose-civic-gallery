require "test_helper"

module DataHealth
  class SnapshotTest < ActiveSupport::TestCase
    test "empty? is true when no ingestion has happened" do
      assert_predicate build_snapshot, :empty?
    end

    test "empty? is false once any record exists" do
      Civic::Matter.create!(legistar_matter_id: 1, matter_file: "26-001")

      assert_not_predicate build_snapshot, :empty?
    end

    test "counts matters, events, and current attachments" do
      matter = Civic::Matter.create!(
        legistar_matter_id: 10,
        matter_file: "26-100",
        agenda_date: Date.new(2026, 5, 1)
      )
      Civic::Event.create!(legistar_event_id: 100, body_name: "City Council", event_date: Date.new(2026, 5, 1))
      Civic::Event.create!(legistar_event_id: 101, body_name: "City Council", event_date: Date.new(2026, 5, 8), source_present: false)
      matter.all_attachments.create!(legistar_matter_attachment_id: 1000, name: "Active")
      matter.all_attachments.create!(legistar_matter_attachment_id: 1001, name: "Retracted", source_present: false)

      snapshot = build_snapshot

      assert_equal 1, snapshot.matter_count
      assert_equal 1, snapshot.event_count
      assert_equal 1, snapshot.attachment_count
    end

    test "matter_date_range covers oldest to newest agenda" do
      Civic::Matter.create!(legistar_matter_id: 1, matter_file: "26-001", agenda_date: Date.new(2024, 6, 12))
      Civic::Matter.create!(legistar_matter_id: 2, matter_file: "26-002", agenda_date: Date.new(2026, 5, 19))

      range = build_snapshot.matter_date_range
      assert_equal Date.new(2024, 6, 12), range.first
      assert_equal Date.new(2026, 5, 19), range.last
    end

    test "most_recent_matter returns the latest agenda" do
      Civic::Matter.create!(legistar_matter_id: 1, matter_file: "26-001", agenda_date: Date.new(2024, 6, 12))
      newer = Civic::Matter.create!(legistar_matter_id: 2, matter_file: "26-575", agenda_date: Date.new(2026, 5, 19))
      Civic::Matter.create!(legistar_matter_id: 3, matter_file: "26-003", agenda_date: nil)

      assert_equal newer.id, build_snapshot.most_recent_matter.id
    end

    test "events_by_body groups, sorts, and rolls up the tail" do
      mk = ->(id, body, n) { n.times { |i| Civic::Event.create!(legistar_event_id: (id * 100) + i, body_name: body, event_date: Date.new(2026, 5, 1)) } }
      mk.call(1, "City Council", 5)
      mk.call(2, "Rules", 3)
      mk.call(3, "Transportation", 2)
      mk.call(4, "Housing", 1)
      mk.call(5, "Parks", 1)

      bodies = build_snapshot.events_by_body

      assert_equal [ [ "City Council", 5 ], [ "Rules", 3 ], [ "Transportation", 2 ] ], bodies[:top]
      assert_equal 2, bodies[:other_body_count]
      assert_equal 2, bodies[:other_count]
    end

    test "reliability counts honor hyperlink and file-attachment presence" do
      matter = Civic::Matter.create!(legistar_matter_id: 1, matter_file: "26-001")
      with_link_imported = matter.all_attachments.create!(
        legistar_matter_attachment_id: 1,
        name: "PDF",
        hyperlink: "https://sanjose.legistar.com/View.ashx?ID=1"
      )
      with_link_imported.source_file.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "a.pdf", content_type: "application/pdf")

      matter.all_attachments.create!(
        legistar_matter_attachment_id: 2,
        name: "Needs import",
        hyperlink: "https://sanjose.legistar.com/View.ashx?ID=2"
      )

      matter.all_attachments.create!(
        legistar_matter_attachment_id: 3,
        name: "No link",
        hyperlink: nil
      )

      snapshot = build_snapshot
      assert_equal 2, snapshot.import_eligible_count
      assert_equal 1, snapshot.imported_count
      assert_equal 1, snapshot.pdf_imported_count
    end

    test "extracted text and summary counts only count successful, current records" do
      matter = Civic::Matter.create!(legistar_matter_id: 1, matter_file: "26-001")
      pdf = matter.all_attachments.create!(
        legistar_matter_attachment_id: 1,
        name: "PDF",
        hyperlink: "https://sanjose.legistar.com/View.ashx?ID=1"
      )
      pdf.source_file.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "a.pdf", content_type: "application/pdf")
      pdf.extracted_texts.create!(extractor_name: "pdftotext", status: "ok", content: "body", character_count: 4)
      pdf.generated_artifacts.create!(
        kind: Generated::SummarizeMatterAttachment::KIND,
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: Generated::SummarizeMatterAttachment::PROMPT::VERSION,
        input_sha256: "abc",
        content: { "summary" => "ok" }
      )

      empty_pdf = matter.all_attachments.create!(
        legistar_matter_attachment_id: 2,
        name: "Empty PDF",
        hyperlink: "https://sanjose.legistar.com/View.ashx?ID=2"
      )
      empty_pdf.source_file.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "b.pdf", content_type: "application/pdf")
      empty_pdf.extracted_texts.create!(extractor_name: "pdftotext", status: "empty")

      stale_summary_pdf = matter.all_attachments.create!(
        legistar_matter_attachment_id: 3,
        name: "Stale summary",
        hyperlink: "https://sanjose.legistar.com/View.ashx?ID=3"
      )
      stale_summary_pdf.source_file.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "c.pdf", content_type: "application/pdf")
      stale_summary_pdf.extracted_texts.create!(extractor_name: "pdftotext", status: "ok", content: "body", character_count: 4)
      stale_summary_pdf.generated_artifacts.create!(
        kind: Generated::SummarizeMatterAttachment::KIND,
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "older_prompt_version",
        input_sha256: "abc",
        content: { "summary" => "stale" }
      )

      snapshot = build_snapshot
      assert_equal 3, snapshot.pdf_imported_count
      assert_equal 2, snapshot.pdf_extracted_count
      assert_equal 2, snapshot.summarizable_count
      assert_equal 1, snapshot.summarized_count
    end

    test "theme_classified_count counts matters with a current-version theme artifact" do
      classified = Civic::Matter.create!(legistar_matter_id: 10, matter_file: "26-010")
      Generated::Artifact.create!(
        target: classified,
        kind: Generated::ClassifyMatterThemes::KIND,
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: Generated::Prompts::MatterThemesV1::VERSION,
        input_sha256: "theme-1",
        content: { "themes" => [ "housing" ] }
      )

      stale = Civic::Matter.create!(legistar_matter_id: 11, matter_file: "26-011")
      Generated::Artifact.create!(
        target: stale,
        kind: Generated::ClassifyMatterThemes::KIND,
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "older_prompt_version",
        input_sha256: "theme-2",
        content: { "themes" => [] }
      )

      Civic::Matter.create!(legistar_matter_id: 12, matter_file: "26-012")

      snapshot = build_snapshot
      assert_equal 1, snapshot.theme_classified_count
      assert_equal 3, snapshot.matter_count
    end

    test "reliability numerators exclude attachments without source links" do
      matter = Civic::Matter.create!(legistar_matter_id: 1, matter_file: "26-001")
      with_link = matter.all_attachments.create!(
        legistar_matter_attachment_id: 1,
        name: "Linked PDF",
        hyperlink: "https://sanjose.legistar.com/View.ashx?ID=1"
      )
      with_link.source_file.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "a.pdf", content_type: "application/pdf")
      with_link.extracted_texts.create!(extractor_name: "pdftotext", status: "ok", content: "body", character_count: 4)

      without_link = matter.all_attachments.create!(
        legistar_matter_attachment_id: 2,
        name: "Local PDF",
        hyperlink: nil
      )
      without_link.source_file.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "b.pdf", content_type: "application/pdf")
      without_link.extracted_texts.create!(extractor_name: "pdftotext", status: "ok", content: "body", character_count: 4)
      without_link.generated_artifacts.create!(
        kind: Generated::SummarizeMatterAttachment::KIND,
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: Generated::SummarizeMatterAttachment::PROMPT::VERSION,
        input_sha256: "abc",
        content: { "summary" => "ok" }
      )

      snapshot = build_snapshot
      assert_equal 1, snapshot.import_eligible_count
      assert_equal 1, snapshot.pdf_imported_count
      assert_equal 1, snapshot.pdf_extracted_count
      assert_equal 1, snapshot.summarizable_count
      assert_equal 0, snapshot.summarized_count
    end

    test "freshness_level is :unknown with no sync, then green/amber/red at boundaries" do
      assert_equal :unknown, build_snapshot.freshness_level

      now = Time.zone.parse("2026-05-18 12:00:00")

      Civic::Matter.create!(
        legistar_matter_id: 1,
        matter_file: "26-001",
        last_synced_at: now - 1.hour
      )
      assert_equal :green, build_snapshot(now: now).freshness_level

      Civic::Matter.update_all(last_synced_at: now - 31.hours)
      assert_equal :amber, build_snapshot(now: now).freshness_level

      Civic::Matter.update_all(last_synced_at: now - 60.hours)
      assert_equal :red, build_snapshot(now: now).freshness_level
    end

    test "last_synced_at takes the max across matters, events, and attachments" do
      newer = Time.zone.parse("2026-05-18 11:00:00")
      older = Time.zone.parse("2026-05-17 11:00:00")

      matter = Civic::Matter.create!(legistar_matter_id: 1, matter_file: "26-001", last_synced_at: older)
      Civic::Event.create!(legistar_event_id: 1, event_date: Date.new(2026, 5, 18), last_synced_at: newer)
      matter.all_attachments.create!(legistar_matter_attachment_id: 1, name: "x", last_synced_at: older)

      assert_equal newer, build_snapshot.last_synced_at
    end

    test "reconciliation counts apply the window" do
      matter = Civic::Matter.create!(legistar_matter_id: 1, matter_file: "26-001")
      Civic::Event.create!(
        legistar_event_id: 1, event_date: Date.new(2026, 4, 1),
        source_present: false, source_missing_at: 10.days.ago
      )
      Civic::Event.create!(
        legistar_event_id: 2, event_date: Date.new(2026, 1, 1),
        source_present: false, source_missing_at: 200.days.ago
      )
      matter.all_attachments.create!(
        legistar_matter_attachment_id: 1, name: "x",
        source_present: false, source_missing_at: 5.days.ago
      )

      snapshot = build_snapshot
      assert_equal 1, snapshot.events_removed_since(30.days.ago)
      assert_equal 1, snapshot.attachments_removed_since(30.days.ago)
    end

    test "cache_key changes when underlying tables are written" do
      first = build_snapshot.cache_key

      travel_to(Time.current.change(usec: 123_456)) do
        Civic::Matter.create!(legistar_matter_id: 1, matter_file: "26-001")
        assert_not_equal first, build_snapshot.cache_key
      end
    end

    test "cache_key preserves sub-second timestamp changes" do
      matter = Civic::Matter.create!(legistar_matter_id: 1, matter_file: "26-001")
      matter.update_column(:updated_at, Time.zone.parse("2026-05-18 12:00:00.100000"))
      first = build_snapshot.cache_key

      matter.update_column(:updated_at, Time.zone.parse("2026-05-18 12:00:00.900000"))

      assert_not_equal first, build_snapshot.cache_key
    end

    private

    def build_snapshot(**options)
      Snapshot.new(jurisdiction: civic_jurisdictions(:sanjose), **options)
    end
  end
end
