require "application_system_test_case"

class PublicMatterDiscoveryTest < ApplicationSystemTestCase
  setup do
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
    @attachment.extracted_texts.create!(
      extractor_name: "pdftotext",
      status: "ok",
      content: "This agreement authorizes a city service contract with clear official source material.",
      character_count: 84,
      extracted_at: Time.current
    )
  end

  test "visitor navigates from meeting to matter and sees document evidence" do
    visit root_path

    click_on "Regular meeting"
    assert_text "Agenda Items"
    assert_text "Linked matter sync pending"

    click_on "26-575"
    assert_selector "p.eyebrow", text: /official matter/i
    assert_text "Agreement approval"
    assert_text "Related Meetings"
    assert_text "Regular meeting"
    assert_text "Official Attachments"
    assert_text "Agreement PDF"
    assert_text "File imported"
    assert_text "Extracted text available"
    assert_text "Extracted Text Preview"
    assert_text "This agreement authorizes"
  end

  test "visitor searches matters by file number" do
    Civic::Matter.create!(
      legistar_matter_id: 15887,
      matter_file: "26-999",
      title: "Unrelated item"
    )

    visit public_matters_path
    within ".search-form" do
      fill_in "Search matters and extracted document text", with: "26-575"
      click_on "Search"
    end

    assert_text "26-575"
    assert_no_text "26-999"
  end

  test "visitor searches extracted document text from the matters index" do
    visit public_matters_path
    within ".search-form" do
      fill_in "Search matters and extracted document text", with: "city service contract"
      click_on "Search"
    end

    assert_text "26-575"
    assert_text "Extracted document text matches"
    assert_text "Agreement PDF"
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
    assert_text "File not imported yet"
    assert_text "Text extraction not available"
    assert_text failed.name
    assert_text "Text extraction failed"
  end
end
