# frozen_string_literal: true

require "test_helper"

module Search
  class SemanticMatterSearchTest < ActiveSupport::TestCase
    setup do
      @jurisdiction = Civic::Jurisdiction.first
      @matter = Civic::Matter.create!(
        legistar_matter_id: 99_005,
        matter_file: "26-667",
        title: "Housing affordability study"
      )
      @other_matter = Civic::Matter.create!(
        legistar_matter_id: 99_006,
        matter_file: "26-668",
        title: "Road repair contract"
      )
      @attachment = @matter.all_attachments.create!(
        legistar_matter_attachment_id: 99_001,
        name: "Housing Report.pdf"
      )

      @artifact = @attachment.generated_artifacts.create!(
        source_artifact: nil,
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "test-v1",
        input_sha256: "abc",
        content: {
          "summary" => "This report discusses affordable housing programs in San Jose.",
          "key_points" => [ "Housing funding" ],
          "limitations" => [ "Generated from extracted text" ],
          "document_status" => "final"
        }
      )

      Search::Embedding.create!(
        civic_jurisdiction: @jurisdiction,
        source_record: @artifact,
        result_record: @matter,
        source_kind: "attachment_summary",
        content_sha256: Digest::SHA256.hexdigest("test"),
        embedding_model: "text-embedding-3-small",
        embedding_dimensions: 1536,
        embedding: [ 0.1 ] * 1536,
        metadata: { artifact_id: @artifact.id }
      )

      # Embedding for other_matter (will match with different vector)
      @other_attachment = @other_matter.all_attachments.create!(
        legistar_matter_attachment_id: 99_002,
        name: "Road Report.pdf"
      )
      @other_artifact = @other_attachment.generated_artifacts.create!(
        source_artifact: nil,
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "test-v1",
        input_sha256: "def",
        content: {
          "summary" => "Road construction contract terms and schedule.",
          "key_points" => [ "Road funding" ],
          "limitations" => [ "Generated from extracted text" ],
          "document_status" => "final"
        }
      )
      Search::Embedding.create!(
        civic_jurisdiction: @jurisdiction,
        source_record: @other_artifact,
        result_record: @other_matter,
        source_kind: "attachment_summary",
        content_sha256: Digest::SHA256.hexdigest("test2"),
        embedding_model: "text-embedding-3-small",
        embedding_dimensions: 1536,
        embedding: [ 0.9 ] * 1536,
        metadata: { artifact_id: @other_artifact.id }
      )

      # Create an embedding for a different jurisdiction (should be excluded)
      @other_jurisdiction = Civic::Jurisdiction.create!(
        slug: "other",
        name: "Other City",
        kind: "city",
        primary_host: "other.example.com",
        source_system_default: "legistar.other"
      )
      @other_jurisdiction_matter = Civic::Matter.create!(
        legistar_matter_id: 99_007,
        matter_file: "26-669",
        title: "Other matter"
      )
      @other_jurisdiction_attachment = @other_jurisdiction_matter.all_attachments.create!(
        legistar_matter_attachment_id: 99_003,
        name: "Other.pdf"
      )
      @other_jurisdiction_artifact = @other_jurisdiction_attachment.generated_artifacts.create!(
        source_artifact: nil,
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "test-v1",
        input_sha256: "ghi",
        content: { "summary" => "Other content" }
      )
      Search::Embedding.create!(
        civic_jurisdiction: @other_jurisdiction,
        source_record: @other_jurisdiction_artifact,
        result_record: @other_jurisdiction_matter,
        source_kind: "attachment_summary",
        content_sha256: Digest::SHA256.hexdigest("test3"),
        embedding_model: "text-embedding-3-small",
        embedding_dimensions: 1536,
        embedding: [ 0.1 ] * 1536,
        metadata: {}
      )
    end

    test "returns matching matters by semantic similarity" do
      # Use a vector close to [0.1] * 1536
      fake_vector = [ 0.1 ] * 1536
      fake_client = stub_client(fake_vector)

      results = SemanticMatterSearch.call(
        query: "affordable housing",
        jurisdiction: @jurisdiction,
        client: fake_client
      )

      matter_ids = results.map(&:matter_id)
      assert_includes matter_ids, @matter.id
      # [0.9] * 1536 is farther from [0.1] * 1536 than [0.1] * 1536 is, so
      # @matter should rank first (smaller cosine distance)
      assert_equal @matter.id, matter_ids.first
    end

    test "returns empty when query is blank" do
      results = SemanticMatterSearch.call(
        query: "",
        jurisdiction: @jurisdiction
      )
      assert_empty results
    end

    test "scopes results to current jurisdiction" do
      fake_vector = [ 0.1 ] * 1536
      fake_client = stub_client(fake_vector)

      results = SemanticMatterSearch.call(
        query: "housing",
        jurisdiction: @jurisdiction,
        client: fake_client
      )

      matter_ids = results.map(&:matter_id)
      assert_includes matter_ids, @matter.id
      assert_not_includes matter_ids, @other_jurisdiction_matter.id
    end

    test "returns empty when embedding client fails" do
      client = EmbeddingClient.new(api_key: "dummy")
      client.define_singleton_method(:embed) do |_input|
        raise EmbeddingClient::RequestError, "API timeout"
      end

      results = SemanticMatterSearch.call(
        query: "housing",
        jurisdiction: @jurisdiction,
        client: client
      )

      assert_empty results
    end

    test "includes provenance with attachment name" do
      fake_vector = [ 0.1 ] * 1536
      fake_client = stub_client(fake_vector)

      results = SemanticMatterSearch.call(
        query: "housing",
        jurisdiction: @jurisdiction,
        client: fake_client
      )

      match = results.find { |r| r.matter_id == @matter.id }
      assert match
      assert_equal "attachment_summary", match.provenance[:kind]
      assert_equal @artifact.id, match.provenance[:artifact_id]
      assert_includes match.provenance[:summary_excerpt], "affordable housing"
      assert_equal "Housing Report.pdf", match.provenance[:attachment_name]
    end

    test "semantic_only? returns true for matter_ids not in keyword set" do
      match = SemanticMatterSearch::SemanticMatch.new(
        matter_id: 999,
        distance: 0.15,
        source_kind: "attachment_summary",
        provenance: {}
      )
      assert match.semantic_only?([ 1, 2, 3 ])
      assert_not match.semantic_only?([ 1, 999, 3 ])
    end

    test "finds matters from event summary embeddings" do
      event_matter = Civic::Matter.create!(
        legistar_matter_id: 88_001,
        matter_file: "26-777",
        title: "Budget hearing matter"
      )
      event = Civic::Event.create!(
        legistar_event_id: 99_999,
        body_name: "City Council",
        title: "Budget hearing on affordable housing",
        event_date: Date.new(2026, 6, 15)
      )
      # Link the matter to the event via an event item
      event.event_items.create!(
        legistar_event_item_id: 99_999,
        civic_matter_id: event_matter.id,
        matter_id: event_matter.legistar_matter_id,
        agenda_sequence: 1,
        agenda_number: "1.1",
        title: "Budget item"
      )

      event_artifact = Generated::Artifact.create!(
        target: event,
        source_artifact: nil,
        kind: "event_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "test-v1",
        input_sha256: "event-digest",
        content: {
          "summary" => "Council discussed affordable housing budget.",
          "key_topics" => [ "Housing funding" ],
          "limitations" => [ "Generated from meeting minutes" ]
        }
      )

      Search::Embedding.create!(
        civic_jurisdiction: @jurisdiction,
        source_record: event_artifact,
        result_record: event,
        source_kind: "event_summary",
        content_sha256: Digest::SHA256.hexdigest("event-digest"),
        embedding_model: "text-embedding-3-small",
        embedding_dimensions: 1536,
        embedding: [ 0.1 ] * 1536,
        metadata: {}
      )

      fake_client = client_for_vector([ 0.1 ] * 1536)

      results = SemanticMatterSearch.call(
        query: "housing budget",
        jurisdiction: @jurisdiction,
        client: fake_client
      )

      matter_ids = results.map(&:matter_id)
      assert_includes matter_ids, event_matter.id

      # Verify provenance includes event info
      match = results.find { |r| r.matter_id == event_matter.id }
      assert_equal "event_summary", match.provenance[:kind]
      assert_equal "Budget hearing on affordable housing", match.provenance[:event_title]
      assert_equal Date.new(2026, 6, 15), match.provenance[:event_date]
    end

    private

    def stub_client(vector)
      client = EmbeddingClient.new(api_key: "test-key")
      client.define_singleton_method(:embed) do |_input|
        EmbeddingClient::Response.new(
          vector: vector,
          model_name: "text-embedding-3-small",
          usage_metadata: {}
        )
      end
      client
    end

    def client_for_vector(vector)
      client = EmbeddingClient.new(api_key: "test-key")
      client.define_singleton_method(:embed) do |_input|
        EmbeddingClient::Response.new(
          vector: vector,
          model_name: "text-embedding-3-small",
          usage_metadata: {}
        )
      end
      client
    end
  end
end
