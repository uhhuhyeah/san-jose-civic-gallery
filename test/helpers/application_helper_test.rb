require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "returns the URL for an https://simbli.eboardsolutions.com link" do
    url = "https://simbli.eboardsolutions.com/Meetings/Attachment.aspx?S=36030421&AID=1488512&MID=57394"
    assert_equal url, official_source_url(url)
  end

  test "returns the URL for an https://sanjose.legistar.com link" do
    assert_equal "https://sanjose.legistar.com/MeetingDetail.aspx?ID=7621",
      official_source_url("https://sanjose.legistar.com/MeetingDetail.aspx?ID=7621")
  end

  test "returns the URL for an https://www.sanjoseca.gov link" do
    assert_equal "https://www.sanjoseca.gov/your-government/appointees/city-clerk/language-access-for-city-council-and-council-committee-meetings",
      official_source_url("https://www.sanjoseca.gov/your-government/appointees/city-clerk/language-access-for-city-council-and-council-committee-meetings")
  end

  test "trims whitespace before validating" do
    assert_equal "https://sanjose.legistar.com/x",
      official_source_url("  https://sanjose.legistar.com/x  ")
  end

  test "rejects http URLs" do
    assert_nil official_source_url("http://sanjose.legistar.com/x")
  end

  test "rejects URLs on other hosts" do
    assert_nil official_source_url("https://evil.example.com/x")
  end

  test "rejects javascript: pseudo-URLs" do
    assert_nil official_source_url("javascript:alert(1)")
  end

  test "returns nil for blank or invalid input" do
    assert_nil official_source_url(nil)
    assert_nil official_source_url("")
    assert_nil official_source_url("not a url at all")
  end

  test "describes attachment import status" do
    matter = Civic::Matter.create!(legistar_matter_id: 90001, matter_file: "26-900")
    attachment = matter.all_attachments.create!(
      legistar_matter_attachment_id: 91001,
      name: "Agreement",
      source_file_import_error: "boom"
    )

    assert_equal "File import failed", attachment_import_status(attachment)

    attachment.update!(source_file_import_error: nil)
    assert_equal "File not imported yet", attachment_import_status(attachment)
  end

  test "describes attachment extraction status" do
    matter = Civic::Matter.create!(legistar_matter_id: 90002, matter_file: "26-901")
    attachment = matter.all_attachments.create!(legistar_matter_attachment_id: 91002, name: "Agreement")

    assert_equal "Text extraction not available", attachment_extraction_status(attachment)

    attachment.source_file.attach(
      io: StringIO.new("%PDF-1.4 fake"),
      filename: "agreement.pdf",
      content_type: "application/pdf"
    )

    assert_equal "Text extraction pending", attachment_extraction_status(attachment)

    attachment.extracted_texts.create!(extractor_name: Documents::ExtractPdfText::EXTRACTOR_NAME, status: "empty")
    assert_equal "Extraction completed with no text", attachment_extraction_status(attachment)

    attachment.extracted_texts.create!(extractor_name: Documents::OcrPdfText::EXTRACTOR_NAME, status: "ok", content: "OCR text")
    assert_equal "OCR text available", attachment_extraction_status(attachment)
  end

  test "describes generated summary status" do
    matter = Civic::Matter.create!(legistar_matter_id: 90003, matter_file: "26-902")
    attachment = matter.all_attachments.create!(legistar_matter_attachment_id: 91003, name: "Agreement")

    assert_equal :not_available, attachment_summary_state(attachment)
    assert_equal "Generated summary not available", attachment_summary_status_text(attachment)

    attachment.source_file.attach(
      io: StringIO.new("%PDF-1.4 fake"),
      filename: "agreement.pdf",
      content_type: "application/pdf"
    )
    extracted_text = attachment.extracted_texts.create!(
      extractor_name: "pdftotext",
      status: "ok",
      content: "Agreement text",
      character_count: 14
    )

    assert_equal :pending, attachment_summary_state(attachment)
    assert_equal "Generated summary pending", attachment_summary_status_text(attachment)

    attachment.generated_artifacts.create!(
      source_artifact: extracted_text,
      kind: Generated::SummarizeMatterAttachment::KIND,
      status: "succeeded",
      model_identifier: "gpt-4o-mini",
      prompt_version: Generated::SummarizeMatterAttachment::PROMPT::VERSION,
      input_sha256: "abc123",
      content: {
        "summary" => "Short generated summary.",
        "key_points" => [],
        "limitations" => [],
        "document_status" => "unknown"
      }
    )

    assert_equal :available, attachment_summary_state(attachment)
    assert_equal "Generated summary available", attachment_summary_status_text(attachment)
  end

  test "describes generated summary unavailable reasons" do
    matter = Civic::Matter.create!(legistar_matter_id: 90004, matter_file: "26-903")
    attachment = matter.all_attachments.create!(legistar_matter_attachment_id: 91004, name: "Agreement")

    assert_equal "The source file has not been imported yet.", attachment_summary_not_available_reason(attachment)

    attachment.source_file.attach(
      io: StringIO.new("%PDF-1.4 fake"),
      filename: "agreement.pdf",
      content_type: "application/pdf"
    )
    attachment.extracted_texts.create!(extractor_name: "pdftotext", status: "empty")
    assert_equal "Extraction completed, but no usable text was found.", attachment_summary_not_available_reason(attachment)

    attachment.extracted_texts.create!(extractor_name: "pdftotext", status: "error", error_message: "boom")
    assert_equal "Text extraction failed for this attachment.", attachment_summary_not_available_reason(attachment)
  end
end
