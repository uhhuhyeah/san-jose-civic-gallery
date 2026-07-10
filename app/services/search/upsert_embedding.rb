module Search
  # Idempotent upsert of embedding rows. If a row with the same source,
  # kind, chunk index, model, and content digest already exists, it is
  # reused. Otherwise a new row is created, preserving the audit trail.
  class UpsertEmbedding
    def self.call(
      source_record:,
      result_record:,
      source_kind:,
      embedding_vector:,
      content_sha256:,
      model_name:,
      dimensions:,
      chunk_index: nil,
      metadata: {}
    )
      new(
        source_record:,
        result_record:,
        source_kind:,
        embedding_vector:,
        content_sha256:,
        model_name:,
        dimensions:,
        chunk_index:,
        metadata:
      ).call
    end

    def initialize(
      source_record:,
      result_record:,
      source_kind:,
      embedding_vector:,
      content_sha256:,
      model_name:,
      dimensions:,
      chunk_index: nil,
      metadata: {}
    )
      @source_record = source_record
      @result_record = result_record
      @source_kind = source_kind
      @embedding_vector = embedding_vector
      @content_sha256 = content_sha256
      @model_name = model_name
      @dimensions = dimensions
      @chunk_index = chunk_index
      @metadata = metadata
    end

    def call
      embedding = Search::Embedding.find_or_initialize_by(
        source_record: @source_record,
        source_kind: @source_kind,
        chunk_index: @chunk_index,
        embedding_model: @model_name,
        content_sha256: @content_sha256
      )

      if embedding.persisted? && embedding.embedding.present?
        return embedding
      end

      jurisdiction = resolve_jurisdiction(@source_record)

      embedding.assign_attributes(
        civic_jurisdiction: jurisdiction,
        result_record: @result_record,
        embedding_dimensions: @dimensions,
        embedding: @embedding_vector,
        metadata: @metadata,
        embedded_at: Time.current
      )
      embedding.save!
      embedding
    end

    private

    def resolve_jurisdiction(record)
      case record
      when Generated::Artifact
        record.target.try(:civic_jurisdiction)
      when Documents::ExtractedText
        record.matter_attachment.try(:civic_jurisdiction)
      else
        record.try(:civic_jurisdiction)
      end
    end
  end
end
