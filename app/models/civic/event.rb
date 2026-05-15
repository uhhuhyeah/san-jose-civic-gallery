module Civic
  class Event < ApplicationRecord
    self.table_name = "civic_events"

    has_many :event_items, -> { agenda_order }, class_name: "Civic::EventItem", foreign_key: :civic_event_id, inverse_of: :event, dependent: :destroy

    validates :legistar_event_id, presence: true, uniqueness: true
    validates :event_date, presence: true

    scope :recent_first, -> { order(event_date: :desc, legistar_event_id: :desc) }

    def display_name
      title.presence || body_name.presence || "Event #{legistar_event_id}"
    end
  end
end
