module Civic
  class Event < ApplicationRecord
    self.table_name = "civic_events"

    include JurisdictionScoped
    include SourceIdentified

    belongs_to :last_source_snapshot, class_name: "Ingestion::SourceSnapshot", optional: true

    has_many :all_event_items, -> { agenda_order }, class_name: "Civic::EventItem", foreign_key: :civic_event_id, inverse_of: :event, dependent: :destroy
    has_many :event_items, -> { current_from_source.agenda_order }, class_name: "Civic::EventItem", foreign_key: :civic_event_id, inverse_of: :event

    validates :source_system, presence: true
    validates :event_date, presence: true

    source_identity generic: :source_event_id, legacy: :legistar_event_id

    scope :current_from_source, -> { where(source_present: true) }
    scope :recent_first, -> { order(event_date: :desc, legistar_event_id: :desc) }

    # Events whose minutes have been published. A meeting summary waits for
    # minutes so it reflects what was actually taken up, not a draft agenda.
    # The predicate matches a present minutes file URI or a final-looking
    # minutes status (e.g. "Final", "Final Revised").
    scope :with_published_minutes, -> {
      where("(minutes_file_uri IS NOT NULL AND minutes_file_uri <> '') OR (minutes_status_name IS NOT NULL AND lower(minutes_status_name) LIKE 'final%')")
    }

    def minutes_published?
      minutes_file_uri.present? || minutes_status_name.to_s.strip.downcase.start_with?("final")
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
