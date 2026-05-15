module Ingestion
  class SyncMatter
    Result = Struct.new(:matter, :snapshot, keyword_init: true)

    def self.call(matter_id:, client: Legistar::Client.new, sync_attachments: true)
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

      SyncMatterAttachments.call(matter:, client:) if sync_attachments

      Result.new(matter:, snapshot:)
    end
  end
end
