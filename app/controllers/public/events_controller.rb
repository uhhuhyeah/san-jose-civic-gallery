module Public
  class EventsController < ApplicationController
    def show
      @event = current_jurisdiction.events
        .includes(event_items: { matter: :attachments })
        .find(params[:id])
      @event_summary = Generated::Artifact
        .succeeded
        .for_kind(Generated::SummarizeEvent::KIND)
        .where(target: @event)
        .recent_first
        .first
      @event_cache_version = Public::CacheVersion.event_show(@event)
      stale?(etag: @event_cache_version, public: true)
    end
  end
end
