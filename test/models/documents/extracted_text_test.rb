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

    test "search finds successful extracted text with ranked snippets" do
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
  end
end
