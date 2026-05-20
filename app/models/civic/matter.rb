module Civic
  class Matter < ApplicationRecord
    self.table_name = "civic_matters"

    include JurisdictionScoped
    include SourceIdentified

    belongs_to :last_source_snapshot, class_name: "Ingestion::SourceSnapshot", optional: true

    has_many :event_items, class_name: "Civic::EventItem", foreign_key: :civic_matter_id, inverse_of: :matter
    has_many :all_attachments, -> { display_order }, class_name: "Civic::MatterAttachment", foreign_key: :civic_matter_id, inverse_of: :matter, dependent: :destroy
    has_many :attachments, -> { current_from_source.display_order }, class_name: "Civic::MatterAttachment", foreign_key: :civic_matter_id, inverse_of: :matter
    has_many :themes, class_name: "Civic::MatterTheme", foreign_key: :civic_matter_id, inverse_of: :matter, dependent: :delete_all

    validates :source_system, presence: true
    validates :matter_file, presence: true

    source_identity generic: :source_matter_id, legacy: :legistar_matter_id

    scope :recent_first, -> { order(agenda_date: :desc, intro_date: :desc, legistar_matter_id: :desc) }
    scope :search, ->(query) {
      normalized = query.to_s.strip
      next all if normalized.blank?

      pattern = "%#{sanitize_sql_like(normalized)}%"
      where(
        "matter_file ILIKE :pattern OR title ILIKE :pattern OR name ILIKE :pattern",
        pattern:
      )
    }

    def display_name
      matter_file.presence || title.presence || "Matter #{legistar_matter_id}"
    end

    def descriptive_title
      title.presence || name.presence
    end
  end
end
