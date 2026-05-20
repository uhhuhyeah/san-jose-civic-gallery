module Public
  class EventsController < ApplicationController
    def show
      @event = current_jurisdiction.events
        .includes(event_items: { matter: :attachments })
        .find(params[:id])
      @event_cache_version = Public::CacheVersion.event_show(@event)
      stale?(etag: @event_cache_version, public: true)
    end
  end
end
