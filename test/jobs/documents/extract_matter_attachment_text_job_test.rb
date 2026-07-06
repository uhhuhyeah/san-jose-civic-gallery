require "test_helper"

module Documents
  class ExtractMatterAttachmentTextJobTest < ActiveJob::TestCase
    test "loads the attachment and delegates text extraction" do
      matter = Civic::Matter.create!(
        legistar_matter_id: 28_001,
        matter_file: "26-801"
      )
      attachment = Civic::MatterAttachment.create!(
        civic_matter_id: matter.id,
        legistar_matter_attachment_id: 38_001,
        name: "Staff Report"
      )
      calls = []

      replace_class_method(ExtractMatterAttachmentText, :call, ->(matter_attachment:) {
        calls << matter_attachment.id
        "extracted"
      }) do
        ExtractMatterAttachmentTextJob.perform_now(attachment.id)
      end

      assert_equal [ attachment.id ], calls
    end

    private

    def replace_class_method(klass, method_name, replacement)
      original = klass.method(method_name)
      klass.define_singleton_method(method_name, &replacement)
      yield
    ensure
      klass.define_singleton_method(method_name, original)
    end
  end
end
