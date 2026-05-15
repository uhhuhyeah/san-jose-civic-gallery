module Civic
  class MatterAttachment < ApplicationRecord
    self.table_name = "civic_matter_attachments"

    belongs_to :matter, class_name: "Civic::Matter", foreign_key: :civic_matter_id, inverse_of: :attachments
    belongs_to :last_source_snapshot, class_name: "Ingestion::SourceSnapshot", optional: true
    has_one_attached :source_file
    has_many :extracted_texts, -> { recent_first }, class_name: "Documents::ExtractedText", foreign_key: :civic_matter_attachment_id, inverse_of: :matter_attachment, dependent: :destroy

    validates :source_system, presence: true
    validates :legistar_matter_attachment_id, presence: true, uniqueness: { scope: :source_system }
    validates :matter, presence: true
    validates :name, presence: true

    scope :current_from_source, -> { where(source_present: true) }
    scope :display_order, -> { order(:sort_order, :legistar_matter_attachment_id) }

    def imported?
      source_file.attached?
    end

    def latest_extracted_text
      extracted_texts.first
    end

    def extracted_text
      latest_extracted_text
    end

    def extractable_as_pdf?
      return false unless source_file.attached?

      source_file.content_type == "application/pdf" ||
        source_file.filename.extension.to_s.downcase == "pdf"
    end
  end
end
