module Public
  class EventsController < ApplicationController
    SHOW_CACHE_TTL = 10.minutes

    def show
      @event = current_jurisdiction.events
        .includes(event_items: { matter: [ :attachments, :themes ] })
        .find(params[:id])
      @event_summary = Generated::Artifact
        .succeeded
        .for_kind(Generated::SummarizeEvent::KIND)
        .where(target: @event)
        .recent_first
        .first
      @event_cache_version = Public::CacheVersion.event_show(@event, jurisdiction: current_jurisdiction)
      load_meeting_atlas_context
      stale?(etag: @event_cache_version, public: true)
    end

    private

    # Atlas sidebar data for the meeting detail page. Themes-on-agenda is
    # aggregated from already-preloaded matter themes; adjacent meetings and
    # the body meeting count come from one shared cache entry.
    def load_meeting_atlas_context
      @tagged_items = Public::AgendaItemClassifier.tag(@event.event_items)
      @substantive_items = @tagged_items.select { |kind, _| kind == :substantive }.map(&:last)
      @notice_items      = @tagged_items.select { |kind, _| kind == :notice }.map(&:last)
      @themes_on_agenda  = aggregate_themes_on_agenda(@substantive_items)
      context = cached_meeting_context
      @previous_event = context[:previous_event]
      @next_event     = context[:next_event]
      @body_meeting_count = context[:body_meeting_count]
    end

    # List of { theme:, count: } for primary themes of substantive items on
    # this agenda, sorted by count descending. Label is `.to_s`-coerced in
    # the secondary sort key so a stray nil label (data error) doesn't raise
    # `ArgumentError: comparison of Array with Array failed`.
    def aggregate_themes_on_agenda(items)
      primary_themes = items.filter_map { |item| item.matter&.themes&.detect { |t| t.rank == 1 } }
      primary_themes
        .group_by(&:theme_slug)
        .values
        .map { |group| { theme: group.first, count: group.length } }
        .sort_by { |entry| [ -entry[:count], entry[:theme].label.to_s ] }
    end

    # Adjacent meetings plus the body meeting count, cached together so a warm
    # page does one cache read instead of three. Each query behind a miss is
    # indexed and cheap.
    def cached_meeting_context
      Rails.cache.fetch([ @event_cache_version, "meeting-context" ], expires_in: SHOW_CACHE_TTL) do
        {
          previous_event: adjacent_event(:previous),
          next_event: adjacent_event(:next),
          body_meeting_count: body_meeting_count
        }
      end
    end

    def adjacent_event(direction)
      scope = current_jurisdiction.events
        .current_from_source
        .where(body_name: @event.body_name)
      case direction
      when :previous
        scope.where(event_date: ...@event.event_date).order(event_date: :desc).first
      when :next
        scope.where("event_date > ?", @event.event_date).order(event_date: :asc).first
      end
    end

    def body_meeting_count
      return 0 if @event.body_name.blank?

      current_jurisdiction.events.current_from_source.where(body_name: @event.body_name).count
    end
  end
end
