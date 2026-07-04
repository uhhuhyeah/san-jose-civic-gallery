module Ingestion
  class SyncMatter
    Result = Struct.new(:matter, :snapshot, keyword_init: true)

    def self.call(matter_id:, client: Legistar::Client.new, sync_attachments: :deferred)
      response = client.matter(matter_id:)

      matter, snapshot = PersistMatter.call(
        matter_payload: response.fetch(:payload),
        source_system: client.source_system,
        request_url: response.fetch(:request_url),
        fetched_at: response.fetch(:fetched_at),
        http_status: response.fetch(:status),
        response_sha256: PayloadDigest.sha256(response.fetch(:payload))
      )

      link_event_items!(matter:)
      FanOut.dispatch(
        mode: sync_attachments,
        inline: -> { SyncMatterAttachments.call(matter:, client:, import_files: :inline) },
        deferred: -> { SyncMatterAttachmentsJob.perform_later(matter.id) }
      )

      Result.new(matter:, snapshot:)
    end

    def self.link_event_items!(matter:)
      Civic::EventItem
        .where(source_system: matter.source_system, matter_id: matter.legistar_matter_id)
        .update_all(
          civic_matter_id: matter.id,
          updated_at: Time.current
        )
    end
    private_class_method :link_event_items!
  end
end
