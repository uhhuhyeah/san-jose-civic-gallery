module Documents
  class ExtractedText < ApplicationRecord
    self.table_name = "document_extracted_texts"

    include BumpsJurisdictionDataVersion

    bumps_jurisdiction_data_version via: :jurisdiction_id_for_data_version

    belongs_to :matter_attachment, class_name: "Civic::MatterAttachment", foreign_key: :civic_matter_attachment_id, inverse_of: :extracted_texts
    has_many :generated_artifacts, as: :source_artifact, class_name: "Generated::Artifact", dependent: :nullify
    scope :recent_first, -> { order(created_at: :desc, id: :desc) }
    scope :successful, -> { where(status: "ok") }
    scope :with_content, -> { where.not(content: [ nil, "" ]) }

    validates :matter_attachment, presence: true
    validates :extractor_name, presence: true

    after_save :sync_attachment_search_projection
    after_destroy :refresh_attachment_search_projection

    SEARCH_INDEX_CHARACTER_LIMIT = 200_000
    SEARCHABLE_CONTENT_SQL = "left(coalesce(document_extracted_texts.content, ''), #{SEARCH_INDEX_CHARACTER_LIMIT})"
    SEARCH_VECTOR_SQL = "to_tsvector('english', #{SEARCHABLE_CONTENT_SQL})"
    SEARCH_MATCH_SQL = "#{SEARCH_VECTOR_SQL} @@ plainto_tsquery('english', ?)"

    def self.search(query)
      matching_latest(query)
        .with_search_snippet(query)
        .order(created_at: :desc, id: :desc)
    end

    def self.matching_latest(query)
      normalized = query.to_s.strip
      return none if normalized.blank?

      successful
        .with_content
        .joins(:matter_attachment)
        .where("civic_matter_attachments.searchable_extracted_text_id = document_extracted_texts.id")
        # Keep this expression aligned with idx_document_extracted_texts_content_search.
        .where(SEARCH_MATCH_SQL, normalized)
    end

    def self.with_search_snippet(query)
      normalized = query.to_s.strip
      return none if normalized.blank?

      tsquery = tsquery_sql(normalized)
      headline_options = "StartSel=<mark>, StopSel=</mark>, MaxWords=24, MinWords=8, ShortWord=3"

      select(
        "#{table_name}.*",
        "ts_headline('english', #{SEARCHABLE_CONTENT_SQL}, #{tsquery}, #{connection.quote(headline_options)}) AS search_snippet"
      )
    end

    def self.tsquery_sql(normalized)
      "plainto_tsquery('english', #{connection.quote(normalized)})"
    end

    private_class_method :tsquery_sql

    private

    def searchable?
      status == "ok" && content.present?
    end

    # The public search projection contains one current successful extraction
    # per attachment. Updating it as text arrives avoids a global DISTINCT ON
    # over every extraction on each anonymous search request.
    def sync_attachment_search_projection
      return refresh_attachment_search_projection unless searchable?

      Civic::MatterAttachment
        .where(id: civic_matter_attachment_id)
        .where(<<~SQL.squish, created_at, created_at, id)
          searchable_extracted_text_id IS NULL OR NOT EXISTS (
            SELECT 1
            FROM document_extracted_texts current_searchable_text
            WHERE current_searchable_text.id = civic_matter_attachments.searchable_extracted_text_id
              AND (
                current_searchable_text.created_at > ? OR
                (current_searchable_text.created_at = ? AND current_searchable_text.id > ?)
              )
          )
        SQL
        .update_all(searchable_extracted_text_id: id)
    end

    def refresh_attachment_search_projection
      attachment = Civic::MatterAttachment.find_by(id: civic_matter_attachment_id)
      return unless attachment&.searchable_extracted_text_id == id

      replacement = self.class.successful.with_content
        .where(civic_matter_attachment_id: attachment.id)
        .order(created_at: :desc, id: :desc)
        .pick(:id)
      attachment.update_column(:searchable_extracted_text_id, replacement)
    end

    def jurisdiction_id_for_data_version
      matter_attachment&.civic_jurisdiction_id
    end
  end
end
