module Documents
  class ExtractedText < ApplicationRecord
    self.table_name = "document_extracted_texts"

    belongs_to :matter_attachment, class_name: "Civic::MatterAttachment", foreign_key: :civic_matter_attachment_id, inverse_of: :extracted_texts
    scope :recent_first, -> { order(created_at: :desc, id: :desc) }

    validates :matter_attachment, presence: true
    validates :extractor_name, presence: true
  end
end
