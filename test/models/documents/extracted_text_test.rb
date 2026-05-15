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
  end
end
