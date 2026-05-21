module Civic
  class MatterAttachment < ApplicationRecord
    self.table_name = "civic_matter_attachments"

    include JurisdictionScoped
    include SourceIdentified

    belongs_to :matter, class_name: "Civic::Matter", foreign_key: :civic_matter_id, inverse_of: :attachments
    belongs_to :last_source_snapshot, class_name: "Ingestion::SourceSnapshot", optional: true
    has_one_attached :source_file
    has_many :extracted_texts, -> { recent_first }, class_name: "Documents::ExtractedText", foreign_key: :civic_matter_attachment_id, inverse_of: :matter_attachment, dependent: :destroy
    has_many :generated_artifacts, as: :target, class_name: "Generated::Artifact", dependent: :destroy

    validates :source_system, presence: true
    validates :matter, presence: true
    validates :name, presence: true

    source_identity generic: :source_attachment_id, legacy: :legistar_matter_attachment_id

    scope :current_from_source, -> { where(source_present: true) }
    scope :display_order, -> { order(:sort_order, :legistar_matter_attachment_id) }
    scope :imported, -> { where.not(source_file_imported_at: nil) }
    # Attachments where the automated importer failed and no operator
    # has stepped in with a manual upload yet. Use this to drive
    # attachments:needs_manual_upload and any human-intervention dashboards.
    scope :needs_manual_upload, -> { where.not(source_file_import_error: nil).where(manually_imported_at: nil) }
    # Attachments with no stored file and no manual upload yet. Broader than
    # needs_manual_upload (which requires a recorded import failure): used for
    # sources whose files are never auto-downloaded (e.g. Simbli, blocked from
    # the server), so the operator can selectively recover documents.
    scope :awaiting_file, -> { where(manually_imported_at: nil).where.missing(:source_file_attachment) }

    def imported?
      source_file.attached?
    end

    def manually_imported?
      manually_imported_at.present?
    end

    def latest_extracted_text
      extracted_texts.first
    end

    def extracted_text
      latest_extracted_text
    end

    def extraction_status
      return "not_imported" unless imported?

      latest_extracted_text&.status || "pending"
    end

    def extractable_as_pdf?
      return false unless source_file.attached?

      source_file.content_type == "application/pdf" ||
        source_file.filename.extension.to_s.downcase == "pdf"
    end
  end
end
