require "test_helper"

module Generated
  class ArtifactTest < ActiveSupport::TestCase
    setup do
      matter = Civic::Matter.create!(
        legistar_matter_id: 15886,
        matter_file: "26-575"
      )
      @attachment = matter.all_attachments.create!(
        legistar_matter_attachment_id: 39135,
        name: "Agreement"
      )
    end

    test "requires provenance and generation metadata" do
      artifact = Artifact.new

      assert_not artifact.valid?
      assert_includes artifact.errors[:target], "must exist"
      assert_includes artifact.errors[:kind], "can't be blank"
      assert_includes artifact.errors[:model_identifier], "can't be blank"
      assert_includes artifact.errors[:prompt_version], "can't be blank"
      assert_includes artifact.errors[:input_sha256], "can't be blank"
    end

    test "allows generated content to target official records without mutating them" do
      artifact = @attachment.generated_artifacts.create!(
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "openai/gpt-4o-mini",
        prompt_version: "attachment_summary_v1",
        input_sha256: "abc123",
        content: { "summary" => "Short summary" }
      )

      assert_equal @attachment, artifact.target
      assert_equal "Agreement", @attachment.reload.name
    end
  end
end
