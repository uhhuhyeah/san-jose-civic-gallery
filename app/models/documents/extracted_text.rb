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
      normalized = query.to_s.strip
      return none if normalized.blank?

      quoted_query = connection.quote(normalized)
      tsquery = "plainto_tsquery('english', #{quoted_query})"
      vector = "to_tsvector('english', coalesce(#{table_name}.content, ''))"
      headline_options = "StartSel=<mark>, StopSel=</mark>, MaxWords=24, MinWords=8, ShortWord=3"

      latest_ok_per_attachment = successful
        .with_content
        .select("DISTINCT ON (civic_matter_attachment_id) id")
        .order(:civic_matter_attachment_id, created_at: :desc, id: :desc)

      where(id: latest_ok_per_attachment)
        .where("#{vector} @@ #{tsquery}")
        .select(
          "#{table_name}.*",
          "ts_rank_cd(#{vector}, #{tsquery}) AS search_rank",
          "ts_headline('english', #{table_name}.content, #{tsquery}, #{connection.quote(headline_options)}) AS search_snippet"
        )
        .order(Arel.sql("search_rank DESC, #{table_name}.created_at DESC, #{table_name}.id DESC"))
    end
  end
end
