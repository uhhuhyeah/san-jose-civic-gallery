module Civic
  class MatterAttachment < ApplicationRecord
    self.table_name = "civic_matter_attachments"

    belongs_to :matter, class_name: "Civic::Matter", foreign_key: :civic_matter_id, inverse_of: :attachments
    has_one_attached :source_file
    has_one :extracted_text, class_name: "Documents::ExtractedText", foreign_key: :civic_matter_attachment_id, inverse_of: :matter_attachment, dependent: :destroy

    validates :legistar_matter_attachment_id, presence: true, uniqueness: true
    validates :matter, presence: true
    validates :name, presence: true

    scope :display_order, -> { order(:sort_order, :legistar_matter_attachment_id) }

    def imported?
      source_file.attached?
    end
  end
end
