module Documents
  class ExtractedText < ApplicationRecord
    self.table_name = "document_extracted_texts"

    belongs_to :matter_attachment, class_name: "Civic::MatterAttachment", foreign_key: :civic_matter_attachment_id, inverse_of: :extracted_texts
    has_many :generated_artifacts, as: :source_artifact, class_name: "Generated::Artifact", dependent: :nullify
    scope :recent_first, -> { order(created_at: :desc, id: :desc) }
    scope :successful, -> { where(status: "ok") }
    scope :with_content, -> { where.not(content: [ nil, "" ]) }

    validates :matter_attachment, presence: true
    validates :extractor_name, presence: true

    def self.search(query)
      matching_latest(query)
        .with_search_snippet(query)
        .order(created_at: :desc, id: :desc)
    end

    def self.matching_latest(query)
      normalized = query.to_s.strip
      return none if normalized.blank?

      latest_ok_per_attachment = successful
        .with_content
        .select("DISTINCT ON (civic_matter_attachment_id) id")
        .order(:civic_matter_attachment_id, created_at: :desc, id: :desc)

      successful
        .with_content
        .where(id: latest_ok_per_attachment)
        .where("#{search_vector_sql} @@ #{tsquery_sql(normalized)}")
    end

    def self.with_search_snippet(query)
      normalized = query.to_s.strip
      return none if normalized.blank?

      tsquery = tsquery_sql(normalized)
      headline_options = "StartSel=<mark>, StopSel=</mark>, MaxWords=24, MinWords=8, ShortWord=3"

      select(
        "#{table_name}.*",
        "ts_headline('english', #{table_name}.content, #{tsquery}, #{connection.quote(headline_options)}) AS search_snippet"
      )
    end

    def self.search_vector_sql
      "to_tsvector('english', coalesce(#{table_name}.content, ''))"
    end

    def self.tsquery_sql(normalized)
      "plainto_tsquery('english', #{connection.quote(normalized)})"
    end

    private_class_method :search_vector_sql, :tsquery_sql
  end
end
