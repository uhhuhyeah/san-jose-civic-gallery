module Public
  class EventsController < ApplicationController
    def index
      @events = Civic::Event.recent_first.limit(8)
      @lead_item = current_event_items.first
      @watch_items = current_event_items.offset(@lead_item ? 1 : 0).limit(3)
      @matter_type_counts = Civic::Matter
        .group(:matter_type_name)
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(6)
        .count
      @stats = {
        meetings: Civic::Event.current_from_source.count,
        agenda_items: Civic::EventItem.current_from_source.count,
        matters: Civic::Matter.count,
        attachments: Civic::MatterAttachment.current_from_source.count,
        imported_files: Civic::MatterAttachment.joins(:source_file_attachment).count,
        extracted_texts: Documents::ExtractedText.where(status: "ok").count
      }
    end

    def show
      @event = Civic::Event
        .includes(event_items: { matter: :attachments })
        .find(params[:id])
    end

    private

    def current_event_items
      Civic::EventItem
        .current_from_source
        .includes(:event, matter: :attachments)
        .where.not(civic_matter_id: nil)
        .joins(:event)
        .merge(Civic::Event.current_from_source)
        .order("civic_events.event_date DESC, civic_event_items.agenda_sequence ASC, civic_event_items.legistar_event_item_id ASC")
    end
  end
end
