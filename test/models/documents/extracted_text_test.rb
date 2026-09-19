require "test_helper"

module Documents
  class ExtractedTextTest < ActiveSupport::TestCase
    setup do
      matter = Civic::Matter.create!(
        legistar_matter_id: 15886,
        matter_file: "26-575"
      )
      @attachment = Civic::MatterAttachment.create!(
        civic_matter_id: matter.id,
        legistar_matter_attachment_id: 39135,
        name: "Agreement"
      )
    end

    test "requires matter attachment and extractor name" do
      extracted_text = ExtractedText.new

      assert_not extracted_text.valid?
      assert_includes extracted_text.errors[:matter_attachment], "must exist"
      assert_includes extracted_text.errors[:extractor_name], "can't be blank"
    end

    test "search finds successful extracted text with snippets" do
      match = @attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "The service agreement includes library outreach and resident access provisions.",
        character_count: 78
      )
      @attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "error",
        content: "library outreach",
        character_count: 16
      )

      results = ExtractedText.search("library outreach").to_a

      assert_equal [ match.id ], results.map(&:id)
      assert_includes results.first.search_snippet, "<mark>library</mark>"
    end

    test "matching latest searches the attachment's current extraction without a global distinct query" do
      sql = ExtractedText.matching_latest("library outreach").to_sql

      assert_includes sql, "civic_matter_attachments.searchable_extracted_text_id = document_extracted_texts.id"
      assert_includes sql, "to_tsvector('english', left(coalesce(document_extracted_texts.content, ''), 200000))"
      assert_not_includes sql, "DISTINCT ON"
      assert_not_includes sql, "ts_rank_cd"
      assert_not_includes sql, "ts_headline"
    end

    test "search returns only the latest successful extraction per attachment" do
      @attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "Older revision mentioning library outreach funding.",
        character_count: 51,
        created_at: 2.days.ago
      )
      latest = @attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "Latest revision mentioning library outreach funding.",
        character_count: 52,
        created_at: 1.day.ago
      )

      results = ExtractedText.search("library outreach").to_a

      assert_equal [ latest.id ], results.map(&:id)
      assert_equal latest.id, @attachment.reload.searchable_extracted_text_id
    end

    test "keeps the latest successful extraction searchable when later extraction states fail or are empty" do
      successful = @attachment.extracted_texts.create!(
        extractor_name: "pdftotext", status: "ok", content: "Library agreement", character_count: 17
      )
      @attachment.extracted_texts.create!(extractor_name: "pdftotext", status: "empty")
      @attachment.extracted_texts.create!(extractor_name: "pdftotext", status: "error", error_message: "bad PDF")

      assert_equal successful.id, @attachment.reload.searchable_extracted_text_id
      assert_equal [ successful.id ], ExtractedText.matching_latest("library").pluck(:id)
    end
  end
end
