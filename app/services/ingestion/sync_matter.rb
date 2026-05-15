module Ingestion
  class SyncMatter
    Result = Struct.new(:matter, :snapshot, keyword_init: true)

    def self.call(matter_id:, client: Legistar::Client.new, sync_attachments: :deferred)
      response = client.matter(matter_id:)

      unless response[:status] == 200
        raise "Legistar Matter request failed with status #{response[:status]} for #{response[:request_url]}"
      end

      matter, snapshot = PersistMatter.call(
        matter_payload: response.fetch(:payload),
        request_url: response.fetch(:request_url),
        fetched_at: response.fetch(:fetched_at),
        http_status: response.fetch(:status),
        response_sha256: response.fetch(:response_sha256)
      )

      link_event_items!(matter:)
      fan_out_attachments(matter:, client:, mode: sync_attachments)

      Result.new(matter:, snapshot:)
    end

    def self.link_event_items!(matter:)
      Civic::EventItem.where(matter_id: matter.legistar_matter_id).update_all(
        civic_matter_id: matter.id,
        updated_at: Time.current
      )
    end
    private_class_method :link_event_items!

    def self.fan_out_attachments(matter:, client:, mode:)
      case normalize_mode(mode)
      when :off
        nil
      when :inline
        SyncMatterAttachments.call(matter:, client:, import_files: :inline)
      when :deferred
        SyncMatterAttachmentsJob.perform_later(matter.id)
      end
    end
    private_class_method :fan_out_attachments

    def self.normalize_mode(mode)
      return :inline if mode == true
      return :off if mode == false

      mode
    end
    private_class_method :normalize_mode
  end
end
