module Public
  class MattersController < ApplicationController
    def index
      @query = params[:q].to_s.strip
      @theme = normalized_theme
      @theme_label = Civic::ThemeTaxonomy.label_for(@theme, current_jurisdiction) if @theme
      return unless stale?(etag: matters_index_cache_version, public: true)

      ids = cached_index_ids
      @document_matches = document_matches_for(ids[:document_match_ids])
      @matters = records_in_cached_order(ids[:matter_ids], Civic::Matter.for_jurisdiction(current_jurisdiction).includes(:attachments, :themes))
      @document_matches_by_matter_id = @document_matches.group_by { |match| match.matter_attachment.matter.id }
    end

    def show
      @matter = current_jurisdiction.matters
        .includes(
          :themes,
          event_items: :event,
          attachments: [
            { source_file_attachment: :blob },
            { extracted_texts: [] },
            { generated_artifacts: [] }
          ]
        )
        .find(params[:id])
      @event_items = @matter.event_items.agenda_order.includes(:event)
      @primary_theme = @matter.themes.detect { |theme| theme.rank == 1 }
      @matter_cache_version = Public::CacheVersion.matter_show(@matter, jurisdiction: current_jurisdiction)
      load_matter_atlas_context
      stale?(etag: @matter_cache_version, public: true)
    end

    private

    SHOW_CACHE_TTL = 10.minutes
    SIBLING_MATTERS_LIMIT = 4

    # Atlas sidebar data for the matter detail page. Each piece is small and
    # cheap to compute, so we co-locate them rather than splitting into another
    # service object. Cached per-matter under the existing matter_cache_version.
    def load_matter_atlas_context
      @latest_event_item = @event_items.max_by { |item| item.event.event_date }
      @latest_event = @latest_event_item&.event
      @sibling_matters = cached_sibling_matter_ids.then do |ids|
        records_in_cached_order(ids, Civic::Matter.for_jurisdiction(current_jurisdiction).includes(:themes))
      end
      @primary_theme_stat = cached_primary_theme_stat
    end

    # Sibling matters from the most recent meeting this matter was heard at.
    # Filters out the matter itself; excluded from rendering when empty.
    def cached_sibling_matter_ids
      Rails.cache.fetch([ @matter_cache_version, "sibling-matter-ids" ], expires_in: SHOW_CACHE_TTL) do
        next [] if @latest_event.nil?

        Civic::Matter
          .for_jurisdiction(current_jurisdiction)
          .joins(:event_items)
          .where(civic_event_items: { civic_event_id: @latest_event.id })
          .where.not(id: @matter.id)
          .distinct
          .limit(SIBLING_MATTERS_LIMIT)
          .pluck(:id)
      end
    end

    # Pulse stat for the matter's primary theme — drives the Atlas-language
    # sidebar tile. Returns nil when the matter has no primary theme yet.
    #
    # Reads from a jurisdiction-scoped cache of the full ThemePulse stats
    # collection rather than rebuilding ThemePulse per matter. Two visits to
    # different matter pages within the same TTL share one set of aggregation
    # queries instead of paying for them on every cold matter page.
    def cached_primary_theme_stat
      return nil unless @primary_theme

      cached_jurisdiction_theme_stats.find { |stat| stat.slug == @primary_theme.theme_slug }
    end

    # Cached jurisdiction-wide ThemePulse stats keyed by jurisdiction + day +
    # data version. Independent of the matter cache version so every matter
    # page in the jurisdiction shares one cache entry, refreshed when the day
    # rolls over or ingestion writes new data.
    def cached_jurisdiction_theme_stats
      Rails.cache.fetch(
        [ "public/theme-pulse-stats", current_jurisdiction.slug, Date.current.iso8601, current_jurisdiction.data_version ],
        expires_in: SHOW_CACHE_TTL
      ) do
        Public::ThemePulse.new(jurisdiction: current_jurisdiction).stats
      end
    end

    INDEX_CACHE_TTL = 5.minutes

    def normalized_theme
      slug = params[:theme].to_s.strip
      slug if Civic::ThemeTaxonomy.valid_slug?(slug, current_jurisdiction)
    end

    def matters_index_cache_version
      @matters_index_cache_version ||= Public::CacheVersion.matters_index(query: @query, theme: @theme, jurisdiction: current_jurisdiction)
    end

    # Both id lists for the index page live in one cache entry because the
    # matter list depends on the document matches: computing them together
    # keeps a warm render at a single cache read and keeps them consistent
    # with each other.
    def cached_index_ids
      Rails.cache.fetch([ matters_index_cache_version, "index-ids" ], expires_in: INDEX_CACHE_TTL) do
        matches = document_match_pairs(@query)
        {
          document_match_ids: matches.map(&:first),
          matter_ids: matter_ids_for(@query, matches.map(&:last).uniq)
        }
      end
    end

    # [extracted_text_id, matter_id] pairs for the top document matches. The
    # matter id rides along in the same pluck so we never load the heavyweight
    # extracted-text rows just to find their matters.
    def document_match_pairs(query)
      return [] if query.blank?

      document_match_candidate_scope(query).limit(20).pluck(:id, Arel.sql("civic_matters.id"))
    end

    def document_matches_for(document_match_ids)
      return [] if document_match_ids.empty?

      records_in_cached_order(document_match_ids, document_match_record_scope(@query))
    end

    def matching_matter_ids(query, document_matter_ids)
      metadata_matches = Civic::Matter.for_jurisdiction(current_jurisdiction).search(query)
      return metadata_matches.select(:id) if document_matter_ids.empty?

      metadata_matches.or(Civic::Matter.for_jurisdiction(current_jurisdiction).where(id: document_matter_ids)).select(:id)
    end

    def document_match_candidate_scope(query)
      Documents::ExtractedText
        .matching_latest(query)
        .joins(matter_attachment: :matter)
        .merge(Civic::MatterAttachment.current_from_source.for_jurisdiction(current_jurisdiction))
        .recent_first
    end

    def document_match_record_scope(query)
      Documents::ExtractedText
        .with_search_snippet(query)
        .joins(matter_attachment: :matter)
        .merge(Civic::MatterAttachment.current_from_source.for_jurisdiction(current_jurisdiction))
        .includes(matter_attachment: :matter)
    end

    def matter_ids_for(query, document_matter_ids)
      scope = Civic::Matter.for_jurisdiction(current_jurisdiction)
      scope = scope.where(id: matching_matter_ids(query, document_matter_ids)) if query.present?
      if @theme
        # Any-rank match (primary or secondary), but surface the matters where
        # this is the primary theme first.
        scope
          .joins(:themes)
          .where(civic_matter_themes: { theme_slug: @theme })
          .order(Arel.sql("civic_matter_themes.rank ASC"))
          .recent_first
          .limit(50)
          .pluck(:id)
      else
        scope.recent_first.limit(50).pluck(:id)
      end
    end

    def records_in_cached_order(ids, scope)
      records_by_id = scope.where(id: ids).index_by(&:id)
      ids.filter_map { |id| records_by_id[id] }
    end
  end
end
