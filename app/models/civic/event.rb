module Civic
  class Event < ApplicationRecord
    self.table_name = "civic_events"

    belongs_to :last_source_snapshot, class_name: "Ingestion::SourceSnapshot", optional: true

    has_many :all_event_items, -> { agenda_order }, class_name: "Civic::EventItem", foreign_key: :civic_event_id, inverse_of: :event, dependent: :destroy
    has_many :event_items, -> { current_from_source.agenda_order }, class_name: "Civic::EventItem", foreign_key: :civic_event_id, inverse_of: :event

    validates :source_system, presence: true
    validates :legistar_event_id, presence: true, uniqueness: { scope: :source_system }
    validates :event_date, presence: true

    scope :current_from_source, -> { where(source_present: true) }
    scope :recent_first, -> { order(event_date: :desc, legistar_event_id: :desc) }

    def display_name
      title.presence || body_name.presence || "Event #{legistar_event_id}"
    end
  end
end
