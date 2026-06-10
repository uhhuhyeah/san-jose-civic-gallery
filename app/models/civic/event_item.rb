module Civic
  class EventItem < ApplicationRecord
    self.table_name = "civic_event_items"

    include JurisdictionScoped
    include SourceIdentified
    include BumpsJurisdictionDataVersion

    bumps_jurisdiction_data_version

    belongs_to :event, class_name: "Civic::Event", foreign_key: :civic_event_id, inverse_of: :event_items
    belongs_to :matter, class_name: "Civic::Matter", foreign_key: :civic_matter_id, inverse_of: :event_items, optional: true
    belongs_to :last_source_snapshot, class_name: "Ingestion::SourceSnapshot", optional: true

    validates :source_system, presence: true
    validates :event, presence: true

    source_identity generic: :source_event_item_id, legacy: :legistar_event_item_id

    scope :current_from_source, -> { where(source_present: true) }
    scope :agenda_order, -> { order(:agenda_sequence, :minutes_sequence, :legistar_event_item_id) }

    def display_name
      agenda_number.presence || title.presence || "Item #{legistar_event_item_id}"
    end
  end
end
