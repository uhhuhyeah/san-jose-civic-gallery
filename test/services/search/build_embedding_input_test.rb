require "test_helper"

module Search
  class BuildEmbeddingInputTest < ActiveSupport::TestCase
    setup do
      @matter = Civic::Matter.create!(
        legistar_matter_id: 99_002,
        matter_file: "26-888"
      )
      @attachment = @matter.all_attachments.create!(
        legistar_matter_attachment_id: 50_001,
        name: "Test Report.pdf"
      )
    end

    test "builds input from attachment_summary artifact" do
      artifact = Generated::Artifact.create!(
        target: @attachment,
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "v1",
        input_sha256: "inp",
        content: {
          "summary" => "This is a test summary",
          "key_points" => [ "Point one", "Point two" ],
          "limitations" => [ "Limitation one" ],
          "document_status" => "draft"
        }
      )

      result = BuildEmbeddingInput.call(artifact)

      assert_includes result, "Summary: This is a test summary"
      assert_includes result, "- Point one"
      assert_includes result, "- Point two"
      assert_includes result, "- Limitation one"
      assert_includes result, "Document status: draft"
    end

    test "builds input from event_summary artifact" do
      artifact = Generated::Artifact.create!(
        target: Civic::Event.create!(
          legistar_event_id: 10_001,
          body_name: "City Council",
          title: "Regular Meeting",
          event_date: Date.new(2026, 6, 1)
        ),
        kind: "event_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "v1",
        input_sha256: "inp2",
        content: {
          "summary" => "Council discussed budget",
          "key_topics" => [ "Budget", "Parks" ],
          "limitations" => [ "Minutes not yet approved" ]
        }
      )

      result = BuildEmbeddingInput.call(artifact)

      assert_includes result, "Summary: Council discussed budget"
      assert_includes result, "- Budget"
      assert_includes result, "- Parks"
      assert_includes result, "- Minutes not yet approved"
    end

    test "raises on unknown artifact kind" do
      artifact = Generated::Artifact.create!(
        target: @attachment,
        kind: "monthly_roundup",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "v1",
        input_sha256: "inp3",
        content: { "summary" => "Roundup" }
      )

      assert_raises(ArgumentError) do
        BuildEmbeddingInput.call(artifact)
      end
    end

    test "handles string key_points (not array)" do
      artifact = Generated::Artifact.create!(
        target: @attachment,
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "v1",
        input_sha256: "inp4",
        content: {
          "summary" => "Test",
          "key_points" => "Single point",
          "limitations" => [],
          "document_status" => "final"
        }
      )

      result = BuildEmbeddingInput.call(artifact)
      assert_includes result, "- Single point"
    end
  end
end
