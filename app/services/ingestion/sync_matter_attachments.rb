module Ingestion
  class SyncMatterAttachments
    Result = Struct.new(:attachments, :snapshots, keyword_init: true)

    def self.call(matter:, client: Legistar::Client.new)
      response = client.matter_attachments(matter_id: matter.legistar_matter_id)

      unless response[:status] == 200
        raise "Legistar MatterAttachments request failed with status #{response[:status]} for #{response[:request_url]}"
      end

      attachments = []
      snapshots = []

      response.fetch(:payload).each do |attachment_payload|
        attachment, snapshot = PersistMatterAttachment.call(
          matter:,
          attachment_payload:,
          request_url: response.fetch(:request_url),
          fetched_at: response.fetch(:fetched_at),
          http_status: response.fetch(:status),
          response_sha256: response.fetch(:response_sha256)
        )
        attachments << attachment
        snapshots << snapshot
      end

      Result.new(attachments:, snapshots:)
    end
  end
end
