require "test_helper"

module Simbli
  class SupportingDocumentsTest < ActiveSupport::TestCase
    test "parses attachment metadata" do
      payload = JSON.parse(file_fixture("simbli/supporting_documents.json").read)
      docs = SupportingDocuments.parse(payload)

      assert_equal [ 5001, 5002 ], docs.map(&:attachment_id)
      assert_equal "Gift Acceptance Memo", docs.first.title
      assert_equal "gift-memo.pdf", docs.first.file_name
      assert_equal "application/pdf", docs.first.content_type
    end

    test "returns empty when there are no attachments" do
      assert_empty SupportingDocuments.parse({ "Attachment" => [] })
      assert_empty SupportingDocuments.parse({})
    end
  end
end
