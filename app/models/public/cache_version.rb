require "digest"

module Public
  class CacheVersion
    class << self
      def events_index
        compose(
          "public/events-index/v1",
          cache_component_for(Civic::Event.current_from_source),
          cache_component_for(Civic::EventItem.current_from_source),
          cache_component_for(Civic::Matter.all),
          cache_component_for(Civic::MatterAttachment.current_from_source),
          cache_component_for(Documents::ExtractedText.all),
          cache_component_for(Generated::Artifact.all)
        )
      end

      def meetings_index(month:, query:, body_name:)
        compose(
          "public/meetings/month-v1",
          month.strftime("%Y-%m"),
          query_digest(query),
          value_digest(body_name),
          cache_component_for(Civic::Event.current_from_source),
          cache_component_for(Civic::EventItem.current_from_source),
          cache_component_for(Civic::Matter.all),
          cache_component_for(Civic::MatterAttachment.current_from_source)
        )
      end

      def event_show(event)
        matter_ids = Civic::EventItem
          .where(civic_event_id: event.id)
          .where.not(civic_matter_id: nil)
          .select(:civic_matter_id)

        compose(
          "public/event-show/v1",
          event.id,
          timestamp_component(event.updated_at),
          cache_component_for(Civic::EventItem.where(civic_event_id: event.id)),
          cache_component_for(Civic::Matter.where(id: matter_ids)),
          cache_component_for(Civic::MatterAttachment.where(civic_matter_id: matter_ids))
        )
      end

      def matter_show(matter)
        attachment_ids = Civic::MatterAttachment.where(civic_matter_id: matter.id).select(:id)
        related_event_ids = Civic::EventItem.where(civic_matter_id: matter.id).select(:civic_event_id)

        compose(
          "public/matter-show/v1",
          matter.id,
          timestamp_component(matter.updated_at),
          cache_component_for(Civic::EventItem.where(civic_matter_id: matter.id)),
          cache_component_for(Civic::Event.where(id: related_event_ids)),
          cache_component_for(Civic::MatterAttachment.where(civic_matter_id: matter.id)),
          cache_component_for(Documents::ExtractedText.where(civic_matter_attachment_id: attachment_ids)),
          cache_component_for(Generated::Artifact.where(target_type: "Civic::MatterAttachment", target_id: attachment_ids))
        )
      end

      def matters_index(query:)
        compose(
          "public/matters-index/v1",
          query_digest(query),
          cache_component_for(Civic::Matter.all),
          cache_component_for(Civic::MatterAttachment.current_from_source),
          cache_component_for(Documents::ExtractedText.all),
          cache_component_for(Generated::Artifact.all)
        )
      end

      def data(snapshot = DataHealth::Snapshot.new)
        compose("public/data/v1", snapshot.cache_key)
      end

      def pulse(as_of:, body_name:, window:)
        compose(
          "public/pulse/v1",
          as_of.to_s,
          window.to_i,
          value_digest(body_name),
          cache_component_for(Civic::MatterTheme.all),
          cache_component_for(Civic::EventItem.current_from_source),
          cache_component_for(Civic::Event.current_from_source)
        )
      end

      def matter_attachment_fragment(attachment, latest_text:, summary_artifact:)
        [
          "public/matter-attachment/v1",
          attachment.cache_key_with_version,
          attachment.source_file_attachment&.cache_key_with_version,
          attachment.source_file_blob&.cache_key_with_version,
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

      def cache_component_for(scope)
        [
          scope.count,
          timestamp_component(scope.maximum(:updated_at))
        ].join(":")
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
