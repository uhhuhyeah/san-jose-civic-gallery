require "test_helper"

module Generated
  module Prompts
    class AttachmentSummaryV1Test < ActiveSupport::TestCase
      test "prompt requires draft language in summary and treats placeholders as missing facts" do
        matter = Civic::Matter.create!(
          legistar_matter_id: 20_001,
          matter_file: "26-100"
        )
        attachment = matter.all_attachments.create!(
          legistar_matter_attachment_id: 30_001,
          name: "Draft agreement"
        )
        extracted_text = attachment.extracted_texts.create!(
          extractor_name: "pdftotext",
          extractor_version: "24.02",
          status: "ok",
          source_file_checksum_sha256: "source-checksum",
          content: "DRAFT\nConsultant name change: Effective [insert date], from ______ to ______.",
          character_count: 78
        )

        prompt = AttachmentSummaryV1.build(
          matter_attachment: attachment,
          extracted_text:,
          max_input_chars: 2_000
        )

        assert_equal "attachment_summary_v3", AttachmentSummaryV1::VERSION
        assert_includes prompt.fetch(:system_prompt), "summary itself"
        assert_includes prompt.fetch(:system_prompt), "appears to be a draft"
        assert_includes prompt.fetch(:system_prompt), "Treat blank fields"
        assert_includes prompt.fetch(:system_prompt), "Do not summarize a"
        assert_includes prompt.fetch(:system_prompt), "placeholder section as an actual completed change"
      end
    end
  end
end
