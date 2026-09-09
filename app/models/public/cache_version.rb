require "digest"

module Public
  # Builds the ETag / cache-key strings for the public pages.
  #
  # Freshness comes from the jurisdiction's data version: a single timestamp
  # bumped after every committed write to a public-facing record (see
  # BumpsJurisdictionDataVersion). Earlier versions of this class derived
  # freshness from COUNT(*) and MAX(updated_at) over each table involved in a
  # page, which meant 10-16 sequential aggregate queries per request before
  # anything rendered. Against a remote database that was most of the page's
  # response time (Sentry RUBY-RAILS-Z).
  #
  # Show-page versions also fold in the record's own id and updated_at; that
  # costs nothing (the record is already loaded) and keeps keys distinct per
  # record. The jurisdiction component means any ingestion write re-renders
  # every page in that jurisdiction on next visit, which is fine: rendering is
  # cheap once the version check is, and the Rails.cache entries behind the
  # pages are keyed on these same strings so they refresh together.
  #
  # Callers pass the request's current_jurisdiction, which is loaded fresh on
  # every request, so a bump is visible to the next request without any extra
  # query here.
  class CacheVersion
    class << self
      def events_index(jurisdiction:)
        compose(
          "public/events-index/v2",
          jurisdiction.slug,
          jurisdiction.data_version
        )
      end

      def meetings_index(month:, query:, body_name:, jurisdiction:)
        compose(
          "public/meetings/month-v3",
          jurisdiction.slug,
          month.strftime("%Y-%m"),
          query_digest(query),
          value_digest(body_name),
          jurisdiction.data_version
        )
      end

      def event_show(event, jurisdiction:)
        compose(
          "public/event-show/v2",
          jurisdiction.slug,
          event.id,
          timestamp_component(event.updated_at),
          jurisdiction.data_version
        )
      end

      def matter_show(matter, jurisdiction:)
        compose(
          "public/matter-show/v2",
          jurisdiction.slug,
          matter.id,
          timestamp_component(matter.updated_at),
          jurisdiction.data_version
        )
      end

      def matters_index(query:, jurisdiction:, theme: nil)
        compose(
          "public/matters-index/v3",
          jurisdiction.slug,
          query_digest(query),
          value_digest(theme),
          jurisdiction.data_version
        )
      end

      # Landing-page versions (issue #152). Same shape as the index versions:
      # jurisdiction component plus the page's own discriminator, so a data
      # bump re-renders every landing page in that jurisdiction and the
      # Rails.cache entries behind them refresh together.
      def topics_index(jurisdiction:)
        compose(
          "public/topics-index/v1",
          jurisdiction.slug,
          jurisdiction.data_version
        )
      end

      def topic_landing(slug:, jurisdiction:)
        compose(
          "public/topic/v1",
          jurisdiction.slug,
          slug,
          jurisdiction.data_version
        )
      end

      def bodies_index(jurisdiction:)
        compose(
          "public/bodies-index/v1",
          jurisdiction.slug,
          jurisdiction.data_version
        )
      end

      def body_landing(slug:, jurisdiction:)
        compose(
          "public/body/v1",
          jurisdiction.slug,
          value_digest(slug),
          jurisdiction.data_version
        )
      end

      def year_landing(year:, jurisdiction:)
        compose(
          "public/year/v1",
          jurisdiction.slug,
          year,
          jurisdiction.data_version
        )
      end

      # Aggregates behind the sitemap's landing-page rows (issue #152).
      def landing_sitemap(jurisdiction:)
        compose(
          "public/landing-sitemap/v1",
          jurisdiction.slug,
          jurisdiction.data_version
        )
      end

      def data(snapshot)
        compose("public/data/v1", snapshot.cache_key)
      end

      def matter_attachment_fragment(attachment, latest_text:, summary_artifact:)
        [
          "public/matter-attachment/v1",
          attachment.cache_key_with_version,
          attachment.source_file_attachment&.cache_key_with_version,
          attachment.source_file_attachment&.blob&.cache_key_with_version,
          latest_text&.cache_key_with_version,
          summary_artifact&.cache_key_with_version
        ]
      end

      def event_agenda_item_fragment(item)
        [
          "public/event-agenda-item/v1",
          item.cache_key_with_version,
          item.matter&.cache_key_with_version,
          item.matter&.attachments&.map(&:cache_key_with_version)
        ]
      end

      def query_digest(value)
        digest_or_blank(value.to_s.strip.downcase)
      end

      private

      def value_digest(value)
        digest_or_blank(value.to_s.strip)
      end

      def digest_or_blank(normalized)
        return "blank" if normalized.blank?

        Digest::SHA256.hexdigest(normalized).first(16)
      end

      def timestamp_component(timestamp)
        timestamp&.utc&.iso8601(6) || "none"
      end

      def compose(*parts)
        parts.join("/")
      end
    end
  end
end
