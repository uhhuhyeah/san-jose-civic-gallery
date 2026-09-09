module Public
  # Durable landing pages for civic bodies (issue #152). Bodies have no table
  # of their own: they are the free-text civic_events.body_name values ("City
  # Council", "Board of Education"). URL slugs are derived at request time
  # from the jurisdiction's distinct body names via String#parameterize, and
  # a slug is reverse-resolved against that same jurisdiction-scoped list, so
  # /bodies/city-council can never surface another host's events.
  #
  # Collision rule: if two body names parameterize to the same slug, the
  # alphabetically first name wins (the candidate list is ordered by name, so
  # `find` is deterministic). The unreachable duplicate remains reachable via
  # /public/meetings?body_name=<name>.
  class BodiesController < ApplicationController
    MEETINGS_LIMIT = 25
    MATTERS_LIMIT = 50
    INDEX_CACHE_TTL = 5.minutes

    def index
      return unless stale?(etag: index_cache_version, public: true)

      @bodies = cached_body_counts
    end

    def show
      body_names = cached_body_names
      @body_name = body_names.find { |name| name.parameterize == params[:slug].to_s }
      unless @body_name
        head :not_found
        return
      end

      return unless stale?(etag: show_cache_version, public: true)

      @events = records_in_cached_order(cached_event_ids, event_scope)
      @matters = records_in_cached_order(cached_matter_ids, matter_scope)
      @empty = @events.empty? && @matters.empty?
    end

    private

    def index_cache_version
      @index_cache_version ||= Public::CacheVersion.bodies_index(jurisdiction: current_jurisdiction)
    end

    def show_cache_version
      @show_cache_version ||= Public::CacheVersion.body_landing(slug: @body_name, jurisdiction: current_jurisdiction)
    end

    # Distinct body names, same query as MeetingsController#cached_filter_options.
    def cached_body_names
      Rails.cache.fetch([ index_cache_version, "body-names" ], expires_in: INDEX_CACHE_TTL) do
        Civic::Event
          .current_from_source
          .for_jurisdiction(current_jurisdiction)
          .where.not(body_name: [ nil, "" ])
          .distinct
          .order(:body_name)
          .pluck(:body_name)
      end
    end

    # Body names paired with their current meeting counts, for the hub tiles.
    # Only bodies with at least one meeting, so the hub never links to a
    # thin (noindex) landing page.
    def cached_body_counts
      Rails.cache.fetch([ index_cache_version, "body-counts" ], expires_in: INDEX_CACHE_TTL) do
        counts = Civic::Event
          .current_from_source
          .for_jurisdiction(current_jurisdiction)
          .where.not(body_name: [ nil, "" ])
          .group(:body_name)
          .count

        counts.keys.sort.map { |name| { name: name, url_slug: name.parameterize, event_count: counts[name] } }
      end
    end

    def event_scope
      Civic::Event.for_jurisdiction(current_jurisdiction).includes(event_items: { matter: :attachments })
    end

    def matter_scope
      Civic::Matter.for_jurisdiction(current_jurisdiction).includes(:attachments, :themes)
    end

    def cached_event_ids
      Rails.cache.fetch([ show_cache_version, "event-ids" ], expires_in: INDEX_CACHE_TTL) do
        Civic::Event
          .current_from_source
          .for_jurisdiction(current_jurisdiction)
          .where(body_name: @body_name)
          .recent_first
          .limit(MEETINGS_LIMIT)
          .pluck(:id)
      end
    end

    # Matters carry the same free-text body_name column events do.
    def cached_matter_ids
      Rails.cache.fetch([ show_cache_version, "matter-ids" ], expires_in: INDEX_CACHE_TTL) do
        Civic::Matter
          .for_jurisdiction(current_jurisdiction)
          .where(body_name: @body_name)
          .recent_first
          .limit(MATTERS_LIMIT)
          .pluck(:id)
      end
    end

    def records_in_cached_order(ids, scope)
      records_by_id = scope.where(id: ids).index_by(&:id)
      ids.filter_map { |id| records_by_id[id] }
    end
  end
end
