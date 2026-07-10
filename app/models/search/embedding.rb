module Search
  class Embedding < ApplicationRecord
    self.table_name = "search_embeddings"

    belongs_to :civic_jurisdiction, class_name: "Civic::Jurisdiction"
    belongs_to :source_record, polymorphic: true
    belongs_to :result_record, polymorphic: true

    has_neighbors :embedding

    validates :source_record, presence: true
    validates :result_record, presence: true
    validates :source_kind, presence: true
    validates :content_sha256, presence: true
    validates :embedding_model, presence: true
    validates :embedding_dimensions, presence: true

    VALID_SOURCE_KINDS = %w[
      attachment_summary
      event_summary
      extracted_text_chunk
      matter_themes
    ].freeze

    validates :source_kind, inclusion: { in: VALID_SOURCE_KINDS }

    scope :for_jurisdiction, ->(jurisdiction) { where(civic_jurisdiction_id: jurisdiction) }
    scope :for_kind, ->(kind) { where(source_kind: kind) }
    scope :recent_first, -> { order(embedded_at: :desc, id: :desc) }
    scope :for_model, ->(model_name) { where(embedding_model: model_name) }
  end
end
