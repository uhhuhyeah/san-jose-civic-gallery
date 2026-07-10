# frozen_string_literal: true

require "set"

module Search
  # Performs semantic search on summary embeddings for matters.
  # Embeds the user query in real time and finds nearest neighbors.
  # Returns an array of SemanticMatch data objects.
  class SemanticMatterSearch
    # Value object for a single semantic match result.
    SemanticMatch = Data.define(
      :matter_id,
      :distance,
      :source_kind,
      :provenance  # Hash with kind, artifact_id, summary_excerpt, attachment_name
    ) do
      def semantic_only?(keyword_ids)
        !keyword_ids.include?(matter_id)
      end
    end

    DEFAULT_LIMIT = 10
    DEFAULT_MAX_DISTANCE = 0.7

    def self.call(query:, jurisdiction:, limit: nil, max_distance: nil, client: nil)
      new(query:, jurisdiction:, limit:, max_distance:, client:).call
    end

    private

    def initialize(query:, jurisdiction:, limit: nil, max_distance: nil, client: nil)
      @query = query.to_s.strip
      @jurisdiction = jurisdiction
      @limit = (limit || ENV.fetch("SEMANTIC_SEARCH_LIMIT", DEFAULT_LIMIT).to_i)
      @max_distance = (max_distance || ENV.fetch("SEMANTIC_SEARCH_MAX_DISTANCE", DEFAULT_MAX_DISTANCE).to_f)
      @client = client || EmbeddingClient.new
    end

    public

    def call
      return [] if @query.blank?

      vector = build_query_embedding
      return [] unless vector

      find_matches(vector)
    end

    private

    def build_query_embedding
      response = @client.embed(@query)
      response.vector
    rescue EmbeddingClient::ConfigurationError, EmbeddingClient::RequestError => e
      Rails.logger.warn(
        "Semantic search embedding failed for query #{@query.inspect}: " \
        "#{e.class}: #{e.message}"
      )
      nil
    end

    def find_matches(vector)
      records = Search::Embedding
        .for_jurisdiction(@jurisdiction)
        .where(source_kind: %w[attachment_summary event_summary])
        .where(result_record_type: %w[Civic::Matter Civic::Event])
        .nearest_neighbors(:embedding, vector, distance: "cosine", threshold: @max_distance)
        .limit(@limit * 2)  # fetch extra to accommodate event → matter expansion
        .to_a

      return [] if records.empty?

      artifact_records = load_source_artifacts(records)
      event_matter_map = resolve_event_matters(records)
      matches = []

      records.each do |record|
        provenance = build_provenance(record, artifact_records[record.source_record_id])

        case record.result_record_type
        when "Civic::Matter"
          matches << SemanticMatch.new(
            matter_id: record.result_record_id,
            distance: record.neighbor_distance,
            source_kind: record.source_kind,
            provenance:
          )
        when "Civic::Event"
          matter_ids = event_matter_map[record.result_record_id] || []
          matter_ids.each do |mid|
            matches << SemanticMatch.new(
              matter_id: mid,
              distance: record.neighbor_distance,
              source_kind: record.source_kind,
              provenance:
            )
          end
        end
      end

      # Dedup by matter_id keeping lowest distance
      seen = Set.new
      matches.select { |m| seen.add?(m.matter_id) }.first(@limit)
    end

    def load_source_artifacts(records)
      artifact_ids = records
        .select { |r| r.source_record_type == "Generated::Artifact" }
        .map(&:source_record_id)

      return {} if artifact_ids.empty?

      Generated::Artifact
        .where(id: artifact_ids)
        .includes(:target)
        .index_by(&:id)
    end

    def build_provenance(record, artifact)
      return {} unless artifact

      case record.source_kind
      when "attachment_summary"
        target = artifact.target
        attachment_name = target.respond_to?(:name) ? target.name : nil
        summary_text = artifact.content.is_a?(Hash) ? artifact.content["summary"].to_s : ""

        {
          kind: "attachment_summary",
          artifact_id: artifact.id,
          summary_excerpt: summary_text.truncate(200),
          attachment_name:
        }
      when "event_summary"
        target = artifact.target
        event_title = target.respond_to?(:title) ? target.title : nil
        event_date = target.respond_to?(:event_date) ? target.event_date : nil
        summary_text = artifact.content.is_a?(Hash) ? artifact.content["summary"].to_s : ""

        {
          kind: "event_summary",
          artifact_id: artifact.id,
          summary_excerpt: summary_text.truncate(200),
          event_title:,
          event_date:
        }
      else
        {
          kind: record.source_kind,
          artifact_id: artifact.id
        }
      end
    end

    def resolve_event_matters(records)
      event_ids = records
        .select { |r| r.result_record_type == "Civic::Event" }
        .map(&:result_record_id)

      return {} if event_ids.empty?

      Civic::EventItem
        .where(civic_event_id: event_ids)
        .pluck(:civic_event_id, :civic_matter_id)
        .group_by(&:first)
        .transform_values { |pairs| pairs.map(&:second).uniq }
    end
  end
end
