require "test_helper"

module Documents
  class ImportMatterAttachmentFileJobTest < ActiveSupport::TestCase
    setup do
      matter = Civic::Matter.create!(
        legistar_matter_id: 15886,
        matter_file: "26-575"
      )
      @attachment = Civic::MatterAttachment.create!(
        civic_matter_id: matter.id,
        legistar_matter_attachment_id: 39135,
        name: "Agreement",
        hyperlink: "https://example.test/agreement.pdf"
      )
      clear_enqueued_jobs
    end

    test "chains text extraction for imported pdfs" do
      original_call = Documents::ImportMatterAttachmentFile.method(:call)

      @attachment.source_file.attach(
        io: StringIO.new("%PDF-1.4 fake"),
        filename: "agreement.pdf",
        content_type: "application/pdf"
      )

      Documents::ImportMatterAttachmentFile.define_singleton_method(:call) do |matter_attachment:|
        matter_attachment.update!(source_file_checksum_sha256: "abc123")
        matter_attachment
      end

      assert_enqueued_with(job: Documents::ExtractMatterAttachmentTextJob, args: [ @attachment.id ]) do
        ImportMatterAttachmentFileJob.perform_now(@attachment.id)
      end
    ensure
      Documents::ImportMatterAttachmentFile.define_singleton_method(:call, original_call)
    end
  end
end
