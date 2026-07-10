require "test_helper"

module Search
  class UpsertEmbeddingTest < ActiveSupport::TestCase
    setup do
      @jurisdiction = civic_jurisdictions(:sanjose)
      @matter = Civic::Matter.create!(
        legistar_matter_id: 99_003,
        matter_file: "26-777"
      )
      @attachment = @matter.all_attachments.create!(
        legistar_matter_attachment_id: 50_002,
        name: "Report.pdf"
      )
    end

    test "creates a new embedding row" do
      artifact = Generated::Artifact.create!(
        target: @attachment,
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "v1",
        input_sha256: "inp",
        content: { "summary" => "Test", "key_points" => [], "limitations" => [], "document_status" => "final" }
      )

      embedding_vector = [ 0.1 ] * 1536
      result = UpsertEmbedding.call(
        source_record: artifact,
        result_record: @matter,
        source_kind: "attachment_summary",
        embedding_vector:,
        content_sha256: "sha-digest",
        model_name: "test-model",
        dimensions: 1536,
        metadata: { "artifact_id" => artifact.id }
      )

      assert result.persisted?
      assert_equal @jurisdiction.id, result.civic_jurisdiction_id
      assert_equal embedding_vector, result.embedding
      assert_equal "sha-digest", result.content_sha256
    end

    test "is idempotent for unchanged inputs" do
      artifact = Generated::Artifact.create!(
        target: @attachment,
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "v1",
        input_sha256: "inp",
        content: { "summary" => "Test", "key_points" => [], "limitations" => [], "document_status" => "final" }
      )

      vector1 = [ 0.1 ] * 1536
      vector2 = [ 0.4 ] * 1536
      first = UpsertEmbedding.call(
        source_record: artifact,
        result_record: @matter,
        source_kind: "attachment_summary",
        embedding_vector: vector1,
        content_sha256: "same-digest",
        model_name: "test-model",
        dimensions: 1536
      )

      second = UpsertEmbedding.call(
        source_record: artifact,
        result_record: @matter,
        source_kind: "attachment_summary",
        embedding_vector: vector2,
        content_sha256: "same-digest",
        model_name: "test-model",
        dimensions: 1536
      )

      assert_equal first.id, second.id
      assert_equal vector1, second.reload.embedding
    end

    test "resolves jurisdiction from Generated::Artifact target" do
      artifact = Generated::Artifact.create!(
        target: @attachment,
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "v1",
        input_sha256: "inp",
        content: { "summary" => "Test", "key_points" => [], "limitations" => [], "document_status" => "final" }
      )

      result = UpsertEmbedding.call(
        source_record: artifact,
        result_record: @matter,
        source_kind: "attachment_summary",
        embedding_vector: [ 0.1 ] * 1536,
        content_sha256: "sha-v2",
        model_name: "test-model",
        dimensions: 1536
      )

      assert_equal @jurisdiction.id, result.civic_jurisdiction_id
    end

    test "stores metadata" do
      artifact = Generated::Artifact.create!(
        target: @attachment,
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "v1",
        input_sha256: "inp",
        content: { "summary" => "Test", "key_points" => [], "limitations" => [], "document_status" => "final" }
      )

      result = UpsertEmbedding.call(
        source_record: artifact,
        result_record: @matter,
        source_kind: "attachment_summary",
        embedding_vector: [ 0.1 ] * 1536,
        content_sha256: "sha-v3",
        model_name: "test-model",
        dimensions: 1536,
        metadata: { "prompt_version" => "v1", "test_key" => "test_value" }
      )

      assert_equal "v1", result.metadata["prompt_version"]
      assert_equal "test_value", result.metadata["test_key"]
    end
  end
end
