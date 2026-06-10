module Civic
  class Event < ApplicationRecord
    self.table_name = "civic_events"

    include JurisdictionScoped
    include SourceIdentified
    include BumpsJurisdictionDataVersion

    bumps_jurisdiction_data_version

    belongs_to :last_source_snapshot, class_name: "Ingestion::SourceSnapshot", optional: true

    has_many :all_event_items, -> { agenda_order }, class_name: "Civic::EventItem", foreign_key: :civic_event_id, inverse_of: :event, dependent: :destroy
    has_many :event_items, -> { current_from_source.agenda_order }, class_name: "Civic::EventItem", foreign_key: :civic_event_id, inverse_of: :event

    validates :source_system, presence: true
    validates :event_date, presence: true

    source_identity generic: :source_event_id, legacy: :legistar_event_id

    scope :current_from_source, -> { where(source_present: true) }
    scope :recent_first, -> { order(event_date: :desc, legistar_event_id: :desc) }

    # Events that have at least one current agenda item, so there is something
    # to summarize. This source (Legistar) publishes finalized agendas but not
    # minutes, so the agenda item set is what a meeting summary draws from. The
    # summary regenerates when that item set changes.
    scope :with_agenda_items, -> {
      where(id: Civic::EventItem.current_from_source.select(:civic_event_id))
    }

    def agenda_items?
      event_items.exists?
    end

    def display_name
      title.presence || body_name.presence || "Event #{legistar_event_id}"
    end

    def listing_title
      return title if title.present? && title != body_name

      "#{body_name.presence || "Meeting"} meeting"
    end
  end
end
