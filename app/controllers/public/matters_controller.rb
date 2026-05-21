module Public
  class MattersController < ApplicationController
    def index
      @query = params[:q].to_s.strip
      @theme = normalized_theme
      @theme_label = Civic::ThemeTaxonomy.label_for(@theme, current_jurisdiction) if @theme
      return unless stale?(etag: matters_index_cache_version, public: true)

      @document_matches = document_matches_for(@query)
      document_matter_ids = @document_matches.map { |match| match.matter_attachment.matter.id }.uniq
      @matters = records_in_cached_order(cached_matter_ids(@query, document_matter_ids), Civic::Matter.for_jurisdiction(current_jurisdiction).includes(:attachments, :themes))
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
      @matter_cache_version = Public::CacheVersion.matter_show(@matter)
      stale?(etag: @matter_cache_version, public: true)
    end

    private

    INDEX_CACHE_TTL = 5.minutes

    def normalized_theme
      slug = params[:theme].to_s.strip
      slug if Civic::ThemeTaxonomy.valid_slug?(slug, current_jurisdiction)
    end

    def matters_index_cache_version
      @matters_index_cache_version ||= Public::CacheVersion.matters_index(query: @query, theme: @theme, jurisdiction: current_jurisdiction)
    end

    def document_matches_for(query)
      return [] if query.blank?

      records_in_cached_order(cached_document_match_ids(query), document_match_scope(query))
    end

    def matching_matter_ids(query, document_matter_ids)
      metadata_matches = Civic::Matter.for_jurisdiction(current_jurisdiction).search(query)
      return metadata_matches.select(:id) if document_matter_ids.empty?

      metadata_matches.or(Civic::Matter.for_jurisdiction(current_jurisdiction).where(id: document_matter_ids)).select(:id)
    end

    def cached_document_match_ids(query)
      Rails.cache.fetch([ matters_index_cache_version, "document-match-ids" ], expires_in: INDEX_CACHE_TTL) do
        document_match_scope(query).limit(20).map(&:id)
      end
    end

    def document_match_scope(query)
      Documents::ExtractedText
        .search(query)
        .joins(matter_attachment: :matter)
        .merge(Civic::MatterAttachment.current_from_source.for_jurisdiction(current_jurisdiction))
        .includes(matter_attachment: :matter)
    end

    def cached_matter_ids(query, document_matter_ids)
      Rails.cache.fetch([ matters_index_cache_version, "matter-ids" ], expires_in: INDEX_CACHE_TTL) do
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
    end

    def records_in_cached_order(ids, scope)
      records_by_id = scope.where(id: ids).index_by(&:id)
      ids.filter_map { |id| records_by_id[id] }
    end
  end
end
