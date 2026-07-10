require "test_helper"

module Search
  class EmbeddingTest < ActiveSupport::TestCase
    setup do
      @jurisdiction = civic_jurisdictions(:sanjose)
      @matter = Civic::Matter.create!(
        legistar_matter_id: 99_001,
        matter_file: "26-999"
      )
    end

    test "valid embedding row" do
      embedding = Search::Embedding.new(
        civic_jurisdiction: @jurisdiction,
        source_record: @matter,
        result_record: @matter,
        source_kind: "attachment_summary",
        content_sha256: "abc123",
        embedding_model: "test-model",
        embedding_dimensions: 1536,
        embedding: [ 0.1 ] * 1536
      )
      assert embedding.valid?
    end

    test "invalid without source_kind" do
      embedding = Search::Embedding.new(
        civic_jurisdiction: @jurisdiction,
        source_record: @matter,
        result_record: @matter,
        content_sha256: "abc123",
        embedding_model: "test-model",
        embedding_dimensions: 1536
      )
      assert_not embedding.valid?
      assert_includes embedding.errors[:source_kind], "can't be blank"
    end

    test "invalid with unknown source_kind" do
      embedding = Search::Embedding.new(
        civic_jurisdiction: @jurisdiction,
        source_record: @matter,
        result_record: @matter,
        source_kind: "unknown_type",
        content_sha256: "abc123",
        embedding_model: "test-model",
        embedding_dimensions: 1536
      )
      assert_not embedding.valid?
      assert_includes embedding.errors[:source_kind], "is not included in the list"
    end

    test "scopes by jurisdiction" do
      other = civic_jurisdictions(:sjusd)
      e1 = Search::Embedding.create!(
        civic_jurisdiction: @jurisdiction,
        source_record: @matter,
        result_record: @matter,
        source_kind: "attachment_summary",
        content_sha256: "abc",
        embedding_model: "test-model",
        embedding_dimensions: 1536,
        embedding: [ 0.1 ] * 1536
      )
      e2 = Search::Embedding.create!(
        civic_jurisdiction: other,
        source_record: @matter,
        result_record: @matter,
        source_kind: "attachment_summary",
        content_sha256: "def",
        embedding_model: "test-model",
        embedding_dimensions: 1536,
        embedding: [ 0.4 ] * 1536
      )

      assert_includes Search::Embedding.for_jurisdiction(@jurisdiction), e1
      assert_not_includes Search::Embedding.for_jurisdiction(@jurisdiction), e2
    end

    test "scopes by source kind" do
      Search::Embedding.create!(
        civic_jurisdiction: @jurisdiction,
        source_record: @matter,
        result_record: @matter,
        source_kind: "attachment_summary",
        content_sha256: "abc",
        embedding_model: "test-model",
        embedding_dimensions: 1536,
        embedding: [ 0.1 ] * 1536
      )
      e2 = Search::Embedding.create!(
        civic_jurisdiction: @jurisdiction,
        source_record: @matter,
        result_record: @matter,
        source_kind: "event_summary",
        content_sha256: "def",
        embedding_model: "test-model",
        embedding_dimensions: 1536,
        embedding: [ 0.4 ] * 1536
      )

      assert_equal [ e2 ], Search::Embedding.for_kind("event_summary").to_a
    end

    test "idempotency constraint prevents duplicate embeddings" do
      attrs = {
        civic_jurisdiction: @jurisdiction,
        source_record: @matter,
        result_record: @matter,
        source_kind: "attachment_summary",
        chunk_index: 0,
        embedding_model: "test-model",
        content_sha256: "same-digest",
        embedding_dimensions: 1536,
        embedding: [ 0.1 ] * 1536
      }
      Search::Embedding.create!(**attrs)

      assert_raises(ActiveRecord::RecordNotUnique) do
        Search::Embedding.create!(**attrs)
      end
    end
  end
end
