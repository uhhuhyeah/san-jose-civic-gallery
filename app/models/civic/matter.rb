module Civic
  class Matter < ApplicationRecord
    self.table_name = "civic_matters"

    has_many :event_items, class_name: "Civic::EventItem", foreign_key: :civic_matter_id, inverse_of: :matter
    has_many :all_attachments, -> { display_order }, class_name: "Civic::MatterAttachment", foreign_key: :civic_matter_id, inverse_of: :matter, dependent: :destroy
    has_many :attachments, -> { current_from_source.display_order }, class_name: "Civic::MatterAttachment", foreign_key: :civic_matter_id, inverse_of: :matter

    validates :legistar_matter_id, presence: true, uniqueness: true
    validates :matter_file, presence: true

    scope :recent_first, -> { order(agenda_date: :desc, intro_date: :desc, legistar_matter_id: :desc) }

    def display_name
      matter_file.presence || title.presence || "Matter #{legistar_matter_id}"
    end
  end
end
