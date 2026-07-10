require "digest"

module Search
  # Finds succeeded generated artifacts without embeddings and creates
  # embedding rows for them. Follows the same batch-idempotent pattern
  # as Generated::BackfillAttachmentSummaries.
  class BackfillSummaryEmbeddings
    DEFAULT_LIMIT = 10

    Result = Data.define(:dry_run, :candidates, :embedded, :skipped, :failed)

    def self.call(limit: DEFAULT_LIMIT, dry_run: true, force: false, client: EmbeddingClient.new)
      new(limit:, dry_run:, force:, client:).call
    end

    def initialize(limit:, dry_run:, force:, client:)
      @limit = limit.to_i
      @dry_run = dry_run
      @force = force
      @client = client
    end

    def call
      candidates = candidate_artifacts
      embedded = 0
      skipped = 0
      failed = 0

      unless @dry_run
        candidates.each do |artifact|
          result = embed_one(artifact)
          case result[:status]
          when :embedded then embedded += 1
          when :skipped then skipped += 1
          else failed += 1
          end
        end
      end

      Result.new(dry_run: @dry_run, candidates:, embedded:, skipped:, failed:)
    end

    private

    def candidate_artifacts
      scope = Generated::Artifact.succeeded
        .where(kind: %w[attachment_summary event_summary])
        .recent_first
        .includes(:target)

      unless @force
        already_embedded = Search::Embedding
          .where(source_record_type: "Generated::Artifact", source_kind: %w[attachment_summary event_summary])
          .select(:source_record_id)
        scope = scope.where.not(id: already_embedded)
      end

      scope.limit(@limit).to_a
    end

    def embed_one(artifact)
      input = BuildEmbeddingInput.call(artifact)
      content_sha256 = Digest::SHA256.hexdigest(input)
      model_name = @client.model_name

      # Idempotency check: skip if an embedding with the same input digest exists
      existing = Search::Embedding.find_by(
        source_record: artifact,
        source_kind: artifact.kind,
        embedding_model: model_name,
        content_sha256:
      )
      return { status: :skipped, reason: "already_embedded" } if existing

      response = @client.embed(input)

      result_record = resolve_result_record(artifact)
      metadata = {
        "artifact_id" => artifact.id,
        "artifact_kind" => artifact.kind,
        "model_identifier" => artifact.model_identifier,
        "prompt_version" => artifact.prompt_version,
        "target_type" => artifact.target_type,
        "target_id" => artifact.target_id
      }

      UpsertEmbedding.call(
        source_record: artifact,
        result_record:,
        source_kind: artifact.kind,
        embedding_vector: response.vector,
        content_sha256:,
        model_name:,
        dimensions: response.vector.size,
        metadata:
      )

      { status: :embedded }
    rescue StandardError => e
      Rails.logger.error(
        "Search::BackfillSummaryEmbeddings failed for artifact #{artifact.id}: " \
        "#{e.class}: #{e.message}"
      )
      { status: :failed, error: e.message }
    end

    def resolve_result_record(artifact)
      case artifact.target
      when Civic::MatterAttachment
        artifact.target.matter
      else
        artifact.target
      end
    end
  end
end
