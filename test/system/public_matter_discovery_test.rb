require "application_system_test_case"

class PublicMatterDiscoveryTest < ApplicationSystemTestCase
  setup do
    travel_to Time.zone.local(2026, 5, 20, 12, 0, 0)

    @event = Civic::Event.create!(
      legistar_event_id: 7622,
      body_name: "City Council",
      title: "Regular meeting",
      event_date: Date.new(2026, 5, 19),
      agenda_status_name: "Final"
    )
    @matter = Civic::Matter.create!(
      legistar_matter_id: 15886,
      matter_file: "26-575",
      title: "Agreement approval",
      matter_status_name: "Agenda Ready",
      matter_type_name: "Council Item",
      body_name: "City Council",
      agenda_date: Date.new(2026, 5, 19)
    )
    @event.event_items.create!(
      legistar_event_item_id: 129630,
      civic_matter_id: @matter.id,
      matter_id: @matter.legistar_matter_id,
      agenda_sequence: 1,
      agenda_number: "3.4",
      title: "Approve agreement"
    )
    @event.event_items.create!(
      legistar_event_item_id: 129631,
      matter_id: 99999,
      matter_file: "26-PENDING",
      agenda_sequence: 2,
      agenda_number: "3.5",
      title: "Pending linked matter"
    )
    @attachment = @matter.all_attachments.create!(
      legistar_matter_attachment_id: 39135,
      name: "Agreement PDF",
      hyperlink: "https://sanjose.legistar.com/View.ashx?M=F&ID=1",
      file_name: "agreement.pdf",
      source_file_checksum_sha256: "abc123def456"
    )
    @attachment.source_file.attach(
      io: StringIO.new("%PDF-1.4 fake"),
      filename: "agreement.pdf",
      content_type: "application/pdf"
    )
    extracted_text = @attachment.extracted_texts.create!(
      extractor_name: "pdftotext",
      status: "ok",
      content: "This agreement authorizes a city service contract with clear official source material.",
      character_count: 84,
      extracted_at: Time.current
    )
    @attachment.generated_artifacts.create!(
      source_artifact: extracted_text,
      kind: Generated::SummarizeMatterAttachment::KIND,
      status: "succeeded",
      model_identifier: "gpt-4o-mini",
      prompt_version: Generated::SummarizeMatterAttachment::PROMPT::VERSION,
      input_sha256: "abc123",
      content: {
        "summary" => "This generated summary helps visitors decide whether to review the agreement.",
        "key_points" => [ "Authorizes a city service contract." ],
        "limitations" => [ "Generated from extracted text." ],
        "document_status" => "unknown"
      }
    )
  end

  teardown do
    travel_back
  end

  test "visitor navigates from meeting to matter and sees document evidence" do
    visit root_path

    within ".atlas-topbar-nav" do
      click_on "Meetings"
    end
    assert_current_path public_meetings_path, ignore_query: true
    assert_text "Use meeting agendas as an entry point"
    assert_text "Regular meeting"

    click_on "Regular meeting"
    # Atlas meeting detail surfaces the agenda + pending-matter hint.
    assert_selector ".atlas-section-head h2 .atlas-em", text: "agenda"
    assert_text "Linked matter sync pending"

    # The substantive matter row's title links to the matter detail. The matter
    # code (26-575) appears as a chip above the title.
    click_on "Agreement approval"
    # Atlas matter detail eyebrow + code chip
    assert_selector ".atlas-matter-eyebrow"
    assert_selector ".atlas-matter-code", text: "26-575"
    assert_text "Agreement approval"
    # "Heard at" sidebar shows the originating meeting (label uppercased by CSS).
    assert_text "HEARD AT"
    assert_text "Regular meeting"
    # Papers section + attachment metadata
    assert_selector ".atlas-section-head h2 .atlas-em", text: "papers"
    assert_text "Agreement PDF"
    # Extract-preview summary label is uppercased by CSS.
    assert_text "EXTRACTED TEXT PREVIEW"
    # The extracted text itself lives inside a collapsed <details> until the
    # reader opens it; assert the markup, not visible content.
    assert_selector ".atlas-paper-extract-body", text: /This agreement authorizes/, visible: :all
    # Summary card with verbatim AI disclaimer (label uppercased by CSS).
    assert_selector ".atlas-summary .atlas-summary-label", text: "GENERATED SUMMARY"
    assert_text "This generated summary helps visitors decide whether to review the agreement."
  end

  test "visitor searches matters by file number" do
    Civic::Matter.create!(
      legistar_matter_id: 15887,
      matter_file: "26-999",
      title: "Unrelated item"
    )

    visit public_matters_path
    within ".atlas-matters-filter" do
      fill_in "Search matters and extracted document text", with: "26-575"
      click_on "Search"
    end

    assert_text "26-575"
    assert_no_text "26-999"
  end

  test "visitor searches extracted document text from the matters index" do
    visit public_matters_path
    within ".atlas-matters-filter" do
      fill_in "Search matters and extracted document text", with: "city service contract"
      click_on "Search"
    end

    assert_text "26-575"
    # Doc-hits label and the attachment link are uppercased via CSS
    # text-transform; assert against the rendered casing.
    assert_text "EXTRACTED DOCUMENT TEXT MATCHES"
    assert_text "AGREEMENT PDF"
    assert_text "city service contract"
  end

  test "visitor sees not-imported and extraction-error states" do
    not_imported = @matter.all_attachments.create!(
      legistar_matter_attachment_id: 39136,
      name: "Memo pending import",
      hyperlink: "https://sanjose.legistar.com/View.ashx?M=F&ID=2"
    )
    failed = @matter.all_attachments.create!(
      legistar_matter_attachment_id: 39137,
      name: "Scanned PDF",
      hyperlink: "https://sanjose.legistar.com/View.ashx?M=F&ID=3"
    )
    failed.source_file.attach(
      io: StringIO.new("%PDF-1.4 scanned"),
      filename: "scanned.pdf",
      content_type: "application/pdf"
    )
    failed.extracted_texts.create!(
      extractor_name: "pdftotext",
      status: "error",
      error_message: "pdftotext failed",
      extracted_at: Time.current
    )

    visit public_matter_path(@matter)

    assert_text not_imported.name
    assert_text "The source file has not been imported yet."
    assert_text failed.name
    assert_text "Text extraction failed"
  end
end
