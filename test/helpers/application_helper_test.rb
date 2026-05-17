require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
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
end
