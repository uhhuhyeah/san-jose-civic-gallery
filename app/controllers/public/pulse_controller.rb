module Public
  # Unlinked work-in-progress preview of the Pulse theme trends. Reachable only
  # by direct URL (/pulse-v2) and marked noindex in the view, so it is not
  # surfaced in nav or search while it is being iterated on. See docs/pulse.md.
  class PulseController < ApplicationController
    WINDOW = Public::ThemePulse::DEFAULT_WINDOW
    HEATING_UP_LIMIT = 8
    TOP_THEMES_LIMIT = 12
    OPTIONS_CACHE_TTL = 5.minutes

    def show
      @body_name = params[:body_name].to_s.strip
      @as_of = Date.current
      return unless stale?(etag: pulse_cache_version, public: true)

      @body_options = cached_body_options
      pulse = Public::ThemePulse.new(as_of: @as_of, body_name: @body_name.presence)
      @heating_up = pulse.heating_up.select { |stat| stat.surging || (stat.lift && stat.lift > 1) }.first(HEATING_UP_LIMIT)
      @top_themes = pulse.top_themes(limit: TOP_THEMES_LIMIT).select { |stat| stat.current_appearances.positive? }
    end

    private

    def pulse_cache_version
      @pulse_cache_version ||= Public::CacheVersion.pulse(as_of: @as_of, body_name: @body_name, window: WINDOW)
    end

    def cached_body_options
      Rails.cache.fetch([ Public::CacheVersion.events_index, "pulse-body-options" ], expires_in: OPTIONS_CACHE_TTL) do
        Civic::Event.current_from_source.where.not(body_name: [ nil, "" ]).distinct.order(:body_name).pluck(:body_name)
      end
    end
  end
end
