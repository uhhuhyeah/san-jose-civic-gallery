module Public
  class MattersController < ApplicationController
    def index
      @query = params[:q].to_s.strip
      @matters = Civic::Matter
        .includes(:attachments)
        .search(@query)
        .recent_first
        .limit(50)
    end

    def show
      @matter = Civic::Matter
        .includes(
          event_items: :event,
          attachments: [
            { source_file_attachment: :blob },
            { extracted_texts: [] }
          ]
        )
        .find(params[:id])
      @event_items = @matter.event_items.agenda_order.includes(:event)
    end
  end
end
