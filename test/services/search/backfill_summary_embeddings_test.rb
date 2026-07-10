require "test_helper"

module Search
  class BackfillSummaryEmbeddingsTest < ActiveSupport::TestCase
    setup do
      @matter = Civic::Matter.create!(
        legistar_matter_id: 99_004,
        matter_file: "26-666"
      )
      @client = FakeEmbeddingClient.new
    end

    test "dry run reports artifacts without embeddings" do
      candidate = artifact("attachment_summary", "candidate-digest")
      already_embedded = artifact("attachment_summary", "embedded-digest")

      # Give the second artifact an embedding so only the first is a candidate
      Search::Embedding.create!(
        civic_jurisdiction: Civic::Jurisdiction.first,
        source_record: already_embedded,
        result_record: @matter,
        source_kind: "attachment_summary",
        content_sha256: "existing",
        embedding_model: "test-model",
        embedding_dimensions: 1536,
        embedding: [ 0.1 ] * 1536
      )

      result = BackfillSummaryEmbeddings.call(limit: 10, dry_run: true, client: @client)

      assert_equal [ candidate.id ], result.candidates.map(&:id)
      assert_equal 0, result.embedded
      assert_equal 0, @client.calls
    end

    test "generate mode creates embeddings for candidates" do
      artifact("attachment_summary", "summary-digest")

      result = BackfillSummaryEmbeddings.call(limit: 10, dry_run: false, client: @client)

      assert_equal 1, result.embedded
      assert_equal 1, Search::Embedding.count
    end

    test "skips artifacts that already have an embedding" do
      art = artifact("attachment_summary", "existing-digest")
      Search::Embedding.create!(
        civic_jurisdiction: Civic::Jurisdiction.first,
        source_record: art,
        result_record: @matter,
        source_kind: "attachment_summary",
        content_sha256: "existing",
        embedding_model: "test-model",
        embedding_dimensions: 1536,
        embedding: [ 0.1 ] * 1536
      )

      result = BackfillSummaryEmbeddings.call(limit: 10, dry_run: false, client: @client)

      # Already-embedded artifacts are excluded from candidates
      assert_empty result.candidates
      assert_equal 0, result.embedded
      assert_equal 1, Search::Embedding.count
    end

    test "forced mode re-embeds even when embedding exists" do
      art = artifact("attachment_summary", "force-digest")
      Search::Embedding.create!(
        civic_jurisdiction: Civic::Jurisdiction.first,
        source_record: art,
        result_record: @matter,
        source_kind: "attachment_summary",
        content_sha256: "force-digest",
        embedding_model: "test-model",
        embedding_dimensions: 1536,
        embedding: [ 0.1 ] * 1536
      )

      result = BackfillSummaryEmbeddings.call(limit: 10, dry_run: false, client: @client, force: true)

      assert_equal 1, result.embedded
    end

    test "skips non-succeeded artifacts" do
      Generated::Artifact.create!(
        target: @matter,
        kind: "attachment_summary",
        status: "failed",
        model_identifier: "test-model",
        prompt_version: "v1",
        input_sha256: "fail-input",
        content: {}
      )

      result = BackfillSummaryEmbeddings.call(limit: 10, dry_run: true, client: @client)

      assert_empty result.candidates
    end

    private

    def artifact(kind, input_sha256)
      attachment = @matter.all_attachments.create!(
        legistar_matter_attachment_id: rand(60_000..99_999),
        name: "Doc-#{input_sha256[0..4]}.pdf"
      )
      Generated::Artifact.create!(
        target: attachment,
        kind:,
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "v1",
        input_sha256:,
        content: {
          "summary" => "Test summary for #{input_sha256}",
          "key_points" => [ "Test point" ],
          "limitations" => [],
          "document_status" => "final"
        }
      )
    end

    class FakeEmbeddingClient
      attr_reader :calls, :model_name, :dimensions

      def initialize
        @calls = 0
        @model_name = "test-model"
        @dimensions = 3
      end

      def embed(input)
        @calls += 1
        EmbeddingClient::Response.new(
          vector: [ 0.1 ] * 1536,
          model_name: @model_name,
          usage_metadata: {}
        )
      end
    end
  end
end
